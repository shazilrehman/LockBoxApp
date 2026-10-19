package com.lockbox.lockbox

import android.Manifest
import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Protection-feature methods on the `com.lockbox/methods` channel:
 * health report, protection foreground service, device-admin uninstall
 * protection, intruder log and the runtime permissions they need.
 *
 * Delegated to from [LockboxMethodCallHandler]; [handle] returns false for
 * methods it doesn't own.
 */
class ProtectionMethodHandler(private val activity: Activity) {

    companion object {
        private const val REQ_CAMERA = 4101
        private const val REQ_NOTIFICATIONS = 4102
    }

    private val context: Context get() = activity.applicationContext
    private val prefs by lazy { LockPreferences(context) }
    private val intruderLog by lazy { IntruderLogStore(context) }

    /** Pending permission results keyed by request code. */
    private val pendingPermission = mutableMapOf<Int, MethodChannel.Result>()

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            // ── Health ──
            "getHealthReport" -> result.success(HealthChecker.report(context))

            // ── Foreground protection service ──
            "setProtectionServiceEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                prefs.setProtectionServiceEnabled(enabled)
                if (enabled) {
                    result.success(ProtectionForegroundService.start(context))
                } else {
                    ProtectionForegroundService.stop(context)
                    result.success(true)
                }
            }

            // ── Device admin (uninstall protection) ──
            "requestDeviceAdmin" -> requestDeviceAdmin(result)
            "removeDeviceAdmin" -> {
                val dpm = context.getSystemService(DevicePolicyManager::class.java)
                if (LockboxDeviceAdminReceiver.isActive(context)) {
                    dpm?.removeActiveAdmin(LockboxDeviceAdminReceiver.component(context))
                }
                result.success(true)
            }

            // ── Intruder log ──
            "setIntruderPhotoConsent" -> {
                val given = call.argument<Boolean>("given") ?: false
                prefs.setIntruderPhotoConsent(given)
                // Withdrawing consent deletes every stored photo.
                if (!given) intruderLog.deleteAllPhotos()
                result.success(true)
            }
            "getIntruderLog" -> result.success(intruderLog.getEntries())
            "getIntruderPhoto" -> {
                val id = call.argument<Number>("id")?.toLong()
                result.success(id?.let { intruderLog.getPhoto(it) })
            }
            "deleteIntruderEntry" -> {
                call.argument<Number>("id")?.toLong()?.let { intruderLog.deleteEntry(it) }
                result.success(true)
            }
            "clearIntruderLog" -> {
                intruderLog.clearAll()
                result.success(true)
            }

            // ── Runtime permissions ──
            "requestCameraPermission" ->
                requestPermission(Manifest.permission.CAMERA, REQ_CAMERA, result)
            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    result.success(true)
                } else {
                    requestPermission(Manifest.permission.POST_NOTIFICATIONS, REQ_NOTIFICATIONS, result)
                }
            }

            else -> return false
        }
        return true
    }

    /** Forwarded from [MainActivity.onRequestPermissionsResult]. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        val pending = pendingPermission.remove(requestCode) ?: return false
        pending.success(
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        )
        return true
    }

    private fun requestDeviceAdmin(result: MethodChannel.Result) {
        if (LockboxDeviceAdminReceiver.isActive(context)) {
            result.success(true)
            return
        }
        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(
                DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                LockboxDeviceAdminReceiver.component(context),
            )
            putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "Lockbox uses device admin only to stop someone else from uninstalling it " +
                    "to get into your locked apps. It does not control, wipe or monitor your device.",
            )
        }
        try {
            activity.startActivity(intent)
            // The Dart side re-checks status via getHealthReport on resume.
            result.success(false)
        } catch (e: Exception) {
            result.error("DEVICE_ADMIN_ERROR", e.localizedMessage, null)
        }
    }

    private fun requestPermission(permission: String, code: Int, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(context, permission) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        // Replace any stale request with the same code.
        pendingPermission.remove(code)?.success(false)
        pendingPermission[code] = result
        ActivityCompat.requestPermissions(activity, arrayOf(permission), code)
    }
}
