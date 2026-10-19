package com.lockbox.lockbox

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils
import androidx.core.content.ContextCompat

/**
 * Single place that answers "is Lockbox actually able to protect right now?".
 * Used by the foreground service (warning notification) and the Dart UI (banner).
 */
object HealthChecker {

    fun isAccessibilityEnabled(context: Context): Boolean {
        val expected = ComponentName(context, LockboxAccessibilityService::class.java)
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':').apply { setString(enabled) }
        while (splitter.hasNext()) {
            if (ComponentName.unflattenFromString(splitter.next()) == expected) return true
        }
        return false
    }

    fun isNotificationListenerEnabled(context: Context): Boolean {
        val expected = ComponentName(context, LockboxNotificationListenerService::class.java)
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == expected }
    }

    fun isOverlayGranted(context: Context): Boolean = Settings.canDrawOverlays(context)

    fun isBatteryExempt(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return pm?.isIgnoringBatteryOptimizations(context.packageName) ?: false
    }

    fun isPostNotificationsGranted(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED

    fun isCameraGranted(context: Context): Boolean =
        ContextCompat.checkSelfPermission(
            context, Manifest.permission.CAMERA,
        ) == PackageManager.PERMISSION_GRANTED

    /**
     * True when the lock engine can't work: Accessibility is off in Settings,
     * or it's "on" but the service isn't running (e.g. crashed / killed by the
     * OEM — Samsung shows this as "Not working").
     */
    fun isLockEngineDown(context: Context): Boolean =
        !isAccessibilityEnabled(context) || !LockboxAccessibilityService.isRunning

    fun report(context: Context): Map<String, Any> {
        val prefs = LockPreferences(context)
        return mapOf(
            "accessibilityEnabled" to isAccessibilityEnabled(context),
            "accessibilityRunning" to LockboxAccessibilityService.isRunning,
            "notificationListenerEnabled" to isNotificationListenerEnabled(context),
            "overlayGranted" to isOverlayGranted(context),
            "batteryExempt" to isBatteryExempt(context),
            "postNotificationsGranted" to isPostNotificationsGranted(context),
            "deviceAdminActive" to LockboxDeviceAdminReceiver.isActive(context),
            "protectionServiceEnabled" to prefs.isProtectionServiceEnabled(),
            "protectionServiceRunning" to ProtectionForegroundService.isRunning,
            "intruderPhotoConsent" to prefs.isIntruderPhotoConsentGiven(),
            "cameraGranted" to isCameraGranted(context),
            "lockedAppCount" to prefs.getLockedApps().size,
        )
    }
}
