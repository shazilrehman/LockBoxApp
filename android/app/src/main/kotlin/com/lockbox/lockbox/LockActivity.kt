package com.lockbox.lockbox

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Bundle
import android.util.Log
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Lock screen hosted by the pre-warmed `lock_engine` [FlutterEngine].
 *
 * Lifecycle per lock event:
 * 1. [AccessibilityService][LockboxAccessibilityService] launches this activity
 *    with the locked package name in [EXTRA_LOCKED_PACKAGE].
 * 2. [configureFlutterEngine] wires the `com.lockbox/lock` MethodChannel and
 *    pushes the locked-app info (name + icon PNG bytes) to the Dart lock screen.
 * 3. The Dart UI shows a PIN pad + biometric button.
 * 4. On success Dart calls `unlockSuccess` → we mark the app unlocked and finish.
 *    On cancel Dart calls `goHome` → we send the user to the home screen.
 * 5. [cleanUpFlutterEngine] tears down the channel; the engine stays alive for
 *    the next lock event ([shouldDestroyEngineWithHost] = false).
 */
class LockActivity : FlutterFragmentActivity() {

    companion object {
        const val EXTRA_LOCKED_PACKAGE = "extra_locked_package"
        private const val TAG = "LockActivity"
        private const val LOCK_CHANNEL = "com.lockbox/lock"

        /**
         * Photo is taken on this failed attempt (once per lock session), so a
         * single owner typo never triggers the camera.
         */
        private const val PHOTO_ON_FAILURE = 2
    }

    private var lockChannel: MethodChannel? = null
    private var lockedPackage: String? = null
    private var failedAttempts = 0
    private var photoTaken = false

    private val isAdminGuard: Boolean
        get() = lockedPackage == LockboxAccessibilityService.GUARD_DEVICE_ADMIN

    /** Package whose label/icon is shown (Lockbox itself for the admin guard). */
    private val displayPackage: String
        get() = if (isAdminGuard) packageName else lockedPackage ?: ""

    // ─────────────────── Engine wiring ───────────────────

    override fun getCachedEngineId(): String = LockboxApplication.LOCK_ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    // ─────────────────── Lifecycle ───────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        lockedPackage = intent?.getStringExtra(EXTRA_LOCKED_PACKAGE)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        lockedPackage = intent.getStringExtra(EXTRA_LOCKED_PACKAGE)
        failedAttempts = 0
        photoTaken = false
        pushLockScreenInfo()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        lockChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOCK_CHANNEL,
        )

        // ── Handle calls FROM Dart ──
        lockChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "unlockSuccess" -> {
                    lockedPackage?.let { pkg ->
                        LockboxAccessibilityService.markUnlocked(pkg)
                        if (!isAdminGuard) {
                            LockboxNotificationListenerService.onAppUnlocked(this, pkg)
                        }
                    }
                    MainActivity.eventStreamHandler?.sendEvent(
                        mapOf(
                            "packageName" to (lockedPackage ?: ""),
                            "eventType" to "app_unlocked",
                            "timestamp" to System.currentTimeMillis(),
                        )
                    )
                    result.success(true)
                    finish()
                }

                "goHome" -> {
                    LockboxAccessibilityService.pendingLockPackage = null
                    val home = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_HOME)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(home)
                    result.success(true)
                    finish()
                }

                "triggerBiometric" -> showBiometricPrompt(result)

                "reportFailedAttempt" -> {
                    recordFailedAttempt()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // ── Push locked-app info TO Dart ──
        pushLockScreenInfo()
    }

    private fun pushLockScreenInfo() {
        val pkg = displayPackage
        lockChannel?.invokeMethod(
            "showLockScreen",
            mapOf(
                "packageName" to (lockedPackage ?: ""),
                "appName" to if (isAdminGuard) "Uninstall protection" else getAppLabel(pkg),
                "iconBytes" to getAppIconBytes(pkg),
            ),
        )
    }

    // ───────────────── Intruder log ─────────────────────

    private fun recordFailedAttempt() {
        failedAttempts++
        val wantPhoto = !photoTaken && failedAttempts >= PHOTO_ON_FAILURE
        if (wantPhoto && IntruderRecorder.canCapture(this)) photoTaken = true

        IntruderRecorder.record(
            context = applicationContext,
            lifecycleOwner = this,
            packageName = if (isAdminGuard) packageName else lockedPackage ?: "",
            reason = if (isAdminGuard) {
                IntruderLogStore.REASON_UNINSTALL_PROTECTION
            } else {
                IntruderLogStore.REASON_WRONG_PIN
            },
            capturePhoto = wantPhoto,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        lockChannel?.setMethodCallHandler(null)
        lockChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Back button fully disabled — user must authenticate or tap the exit button. */
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Intentionally empty
    }

    override fun onPause() {
        super.onPause()
        // Clear the pending flag if this activity is leaving the foreground
        // without an explicit unlock (e.g. swiped from recents).
        if (LockboxAccessibilityService.pendingLockPackage == lockedPackage) {
            LockboxAccessibilityService.pendingLockPackage = null
        }
    }

    // ───────────────── BiometricPrompt ───────────────────

    private fun showBiometricPrompt(channelResult: MethodChannel.Result) {
        val biometricManager = BiometricManager.from(this)
        // Allow BIOMETRIC_STRONG (fingerprint) and BIOMETRIC_WEAK (Samsung 2D face unlock).
        // Omitting DEVICE_CREDENTIAL enforces biometricOnly per security requirements.
        val authenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG or
            BiometricManager.Authenticators.BIOMETRIC_WEAK

        val canAuth = biometricManager.canAuthenticate(authenticators)
        if (canAuth != BiometricManager.BIOMETRIC_SUCCESS) {
            Log.d(TAG, "Biometric auth unavailable (code: $canAuth); falling back to PIN")
            channelResult.success(false)
            return
        }

        val executor = ContextCompat.getMainExecutor(this)

        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                channelResult.success(true)
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                Log.d(TAG, "Biometric auth error/cancel ($errorCode: $errString); falling back to PIN")
                channelResult.success(false)
            }

            override fun onAuthenticationFailed() {
                // Single attempt failed — BiometricPrompt stays open for retry
            }
        }

        val prompt = BiometricPrompt(this, executor, callback)

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Lockbox")
            .setSubtitle(
                if (isAdminGuard) {
                    "Authenticate to change uninstall protection"
                } else {
                    "Authenticate to open ${getAppLabel(displayPackage)}"
                }
            )
            .setAllowedAuthenticators(authenticators)
            .setNegativeButtonText("Use PIN")
            .build()

        prompt.authenticate(info)
    }

    // ───────────────── Helpers ───────────────────────────

    private fun getAppLabel(packageName: String): String {
        return try {
            val ai = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(ai).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            packageName
        }
    }

    private fun getAppIconBytes(packageName: String): ByteArray? {
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)

            val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
                Bitmap.createScaledBitmap(drawable.bitmap, 128, 128, true)
            } else {
                val w = drawable.intrinsicWidth.coerceAtLeast(128)
                val h = drawable.intrinsicHeight.coerceAtLeast(128)
                val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                Bitmap.createScaledBitmap(bmp, 128, 128, true)
            }

            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to get app icon: ${e.message}")
            null
        }
    }
}
