package com.lockbox.lockbox

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager

/**
 * Core lock engine.
 *
 * Listens for [AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED] to detect
 * foreground-package transitions, checks against the locked-app set,
 * and launches [LockActivity] when authentication is required.
 *
 * ## Re-lock timeout
 * | Mode          | Behaviour                                          |
 * |---------------|----------------------------------------------------|
 * | IMMEDIATE     | Every foreground switch requires auth               |
 * | SCREEN_OFF    | Unlocked until the screen turns off                 |
 * | TIMED         | Unlocked for N minutes after successful auth        |
 *
 * ## Lock-loop prevention
 * 1. Own package (`com.lockbox.lockbox`) is always ignored.
 * 2. Home launchers are resolved at startup and ignored.
 * 3. System UI (`com.android.systemui`) is ignored.
 * 4. A [pendingLockPackage] flag prevents re-triggering while
 *    [LockActivity] is in the foreground.
 * 5. After successful auth the package is added to [unlockedApps]
 *    and honoured according to the active [TimeoutMode]. In IMMEDIATE
 *    mode the grant lasts until the user switches to another app, so
 *    returning to the just-unlocked app doesn't re-lock it.
 *
 * ## Uninstall protection
 * When the device-admin receiver is active, the Settings screen that
 * deactivates it is locked under [GUARD_DEVICE_ADMIN].
 */
class LockboxAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "LockboxA11y"
        private const val DEFAULT_SETTINGS_PACKAGE = "com.android.settings"

        /**
         * Pseudo lock key used when the device-admin deactivation screen is
         * guarded. Passed to [LockActivity] in place of a package name.
         */
        const val GUARD_DEVICE_ADMIN = "lockbox.guard.device_admin"

        // ── Shared state (accessible from LockActivity) ─────

        /**
         * Map of package-name → unlock-timestamp (epoch ms).
         * Written by [LockActivity.markUnlocked], read by the service.
         */
        val unlockedApps: MutableMap<String, Long> = mutableMapOf()

        /**
         * Package currently being locked — set before launching
         * [LockActivity], cleared by [LockActivity] when it finishes.
         * Prevents the service from re-triggering for the same package.
         */
        @Volatile
        var pendingLockPackage: String? = null

        /**
         * True while the service is bound by the system. Used by [HealthChecker]
         * to detect "enabled in Settings but not running" (crash / OEM kill).
         */
        @Volatile
        var isRunning: Boolean = false
            private set

        /** Clear all unlock grants (called on screen-off). */
        fun clearAllUnlocked() {
            unlockedApps.clear()
            Log.d(TAG, "All unlock grants cleared")
        }

        /** Clear unlock grant for a single package. */
        fun clearUnlocked(packageName: String) {
            unlockedApps.remove(packageName)
        }

        /** Grant unlock for [packageName]. */
        fun markUnlocked(packageName: String) {
            unlockedApps[packageName] = System.currentTimeMillis()
            pendingLockPackage = null
            Log.d(TAG, "Unlocked: $packageName")
        }
    }

    private lateinit var prefs: LockPreferences
    private val launcherPackages = mutableSetOf<String>()
    private val imePackages = mutableSetOf<String>()
    private val launchableCache = HashMap<String, Boolean>()
    private var settingsPackage: String = DEFAULT_SETTINGS_PACKAGE
    private var screenOffReceiver: ScreenOffReceiver? = null

    /**
     * Last package that caused a lock-screen launch.
     * Used together with a cooldown to prevent rapid-fire triggers
     * when the window-state bounces between the locked app and
     * [LockActivity].
     */
    private var lastTriggeredPackage: String? = null
    private var lastTriggerTime: Long = 0L
    private val triggerCooldownMs = 1_500L

    // ─────────────────── Lifecycle ───────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        prefs = LockPreferences(this)
        resolveLauncherPackages()
        resolveSettingsPackage()
        resolveImePackages()
        launchableCache.clear()
        registerScreenOffReceiver()
        isRunning = true
        ProtectionForegroundService.requestHealthCheck()
        Log.i(TAG, "Service connected — launchers: $launcherPackages")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        markStopped()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        markStopped()
        unregisterScreenOffReceiver()
        super.onDestroy()
    }

    private fun markStopped() {
        if (!isRunning) return
        isRunning = false
        ProtectionForegroundService.requestHealthCheck()
    }

    // ─────────────────── Event handling ──────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val packageName = event.packageName?.toString() ?: return
        val className = event.className?.toString()

        // ── 1. Ignore own package (LockActivity lives here) ──
        if (packageName == applicationContext.packageName) return

        // ── 2. Ignore system UI and keyboards (transient overlays) ──
        if (packageName == "com.android.systemui") return
        if (packageName in imePackages) return

        // ── 3. A real app switch revokes grants that no longer apply ──
        revokeGrantsOnAppSwitch(packageName)

        // ── 4. Ignore home launchers ──
        if (packageName in launcherPackages) return

        // ── 5. Ignore if a lock screen is already pending ──
        if (pendingLockPackage != null) return

        // ── 6. What (if anything) does this window need to be locked as? ──
        val lockKey = when {
            isDeviceAdminDeactivationScreen(packageName, className) -> GUARD_DEVICE_ADMIN
            prefs.isAppLocked(packageName) -> packageName
            else -> return
        }

        // ── 7. Cooldown — avoid rapid re-triggers ──
        val now = System.currentTimeMillis()
        if (lockKey == lastTriggeredPackage &&
            now - lastTriggerTime < triggerCooldownMs
        ) return

        // ── 8. Is it currently unlocked (within timeout)? ──
        val unlocked = if (lockKey == GUARD_DEVICE_ADMIN) {
            unlockedApps.containsKey(GUARD_DEVICE_ADMIN)
        } else {
            isWithinUnlockWindow(lockKey)
        }
        if (unlocked) return

        // ── All checks passed — launch lock screen ──
        lastTriggeredPackage = lockKey
        lastTriggerTime = now
        pendingLockPackage = lockKey

        launchLockScreen(lockKey)

        // Push event to Flutter (if the engine is alive)
        MainActivity.eventStreamHandler?.sendEvent(
            mapOf(
                "packageName" to lockKey,
                "eventType" to "app_blocked",
                "timestamp" to now,
            )
        )
    }

    override fun onInterrupt() {
        Log.w(TAG, "Service interrupted")
    }

    // ──────────────── Unlock-window check ────────────────

    private fun isWithinUnlockWindow(packageName: String): Boolean {
        val unlockTime = unlockedApps[packageName] ?: return false

        return when (prefs.getTimeoutMode()) {
            TimeoutMode.IMMEDIATE -> {
                // Valid only while the user stays inside the app; the grant is
                // dropped by [revokeGrantsOnAppSwitch] as soon as they leave.
                true
            }
            TimeoutMode.SCREEN_OFF -> {
                // Stays unlocked until ScreenOffReceiver clears it
                true
            }
            TimeoutMode.TIMED -> {
                val elapsedMs = System.currentTimeMillis() - unlockTime
                val windowMs = prefs.getTimeoutMinutes() * 60_000L
                if (elapsedMs < windowMs) {
                    true
                } else {
                    // Expired — remove stale grant
                    unlockedApps.remove(packageName)
                    false
                }
            }
        }
    }

    // ──────────────── Launch LockActivity ────────────────

    private fun launchLockScreen(packageName: String) {
        Log.d(TAG, "Launching lock screen for $packageName")

        val intent = Intent(this, LockActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
            )
            putExtra(LockActivity.EXTRA_LOCKED_PACKAGE, packageName)
        }
        startActivity(intent)
    }

    // ──────────────── Launcher resolution ────────────────

    private fun resolveLauncherPackages() {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
        }
        val resolveInfos: List<ResolveInfo> =
            packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)

        launcherPackages.clear()
        for (info in resolveInfos) {
            info.activityInfo?.packageName?.let { launcherPackages.add(it) }
        }
    }

    private fun resolveSettingsPackage() {
        settingsPackage = Intent(Settings.ACTION_SETTINGS)
            .resolveActivity(packageManager)?.packageName
            ?: DEFAULT_SETTINGS_PACKAGE
    }

    private fun resolveImePackages() {
        val imm = getSystemService(InputMethodManager::class.java) ?: return
        imePackages.clear()
        imm.enabledInputMethodList.forEach { imePackages.add(it.packageName) }
    }

    /** True if [pkg] has a launcher icon, i.e. switching to it is a real app switch. */
    private fun isLaunchableApp(pkg: String): Boolean =
        launchableCache.getOrPut(pkg) { packageManager.getLaunchIntentForPackage(pkg) != null }

    // ────────────── Grant revocation ────────────────────

    /**
     * Drops grants the user has walked away from.
     *
     * Only counts *real* app switches (launcher or an app with a launcher icon),
     * so transient windows — permission dialogs, share sheets, keyboards — that
     * appear on top of an unlocked app don't force a re-lock.
     *
     * - IMMEDIATE mode: all grants except the foreground app's are revoked.
     * - Device-admin guard: always revoked once the user leaves Settings.
     */
    private fun revokeGrantsOnAppSwitch(foreground: String) {
        if (unlockedApps.isEmpty()) return
        if (foreground !in launcherPackages && !isLaunchableApp(foreground)) return

        val immediate = prefs.getTimeoutMode() == TimeoutMode.IMMEDIATE
        val iterator = unlockedApps.keys.iterator()
        while (iterator.hasNext()) {
            val key = iterator.next()
            if (key == GUARD_DEVICE_ADMIN) {
                if (foreground != settingsPackage) iterator.remove()
            } else if (immediate && key != foreground) {
                iterator.remove()
            }
        }
    }

    // ───────────── Uninstall-protection guard ─────────────

    /**
     * The Settings screen that deactivates a device admin (`DeviceAdminAdd`,
     * same class name on AOSP, Pixel and Samsung One UI). While our admin is
     * active, Android blocks uninstall until it is deactivated here — so this
     * screen is gated behind the Lockbox PIN.
     */
    private fun isDeviceAdminDeactivationScreen(pkg: String, className: String?): Boolean =
        pkg == settingsPackage &&
            className?.contains("DeviceAdminAdd") == true &&
            LockboxDeviceAdminReceiver.isActive(this)

    // ────────────── Screen-off receiver ──────────────────

    private fun registerScreenOffReceiver() {
        screenOffReceiver = ScreenOffReceiver(onScreenOff = {
            if (prefs.getTimeoutMode() == TimeoutMode.TIMED) {
                // Timed grants survive screen-off, but the admin guard never does.
                unlockedApps.remove(GUARD_DEVICE_ADMIN)
            } else {
                clearAllUnlocked()
            }
        })
        registerReceiver(screenOffReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }

    private fun unregisterScreenOffReceiver() {
        screenOffReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // Already unregistered
            }
        }
        screenOffReceiver = null
    }
}
