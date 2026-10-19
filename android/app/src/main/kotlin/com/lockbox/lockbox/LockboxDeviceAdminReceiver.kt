package com.lockbox.lockbox

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Device-admin receiver used ONLY for uninstall protection.
 *
 * While this admin is active, Android refuses to uninstall Lockbox until the
 * admin is deactivated. Deactivation itself is guarded by the accessibility
 * service, which shows the Lockbox lock screen over the device-admin settings
 * page (see [LockboxAccessibilityService]).
 *
 * Requests no policies (`<uses-policies/>` is empty in device_admin.xml).
 */
class LockboxDeviceAdminReceiver : DeviceAdminReceiver() {

    companion object {
        private const val TAG = "LockboxDeviceAdmin"

        fun component(context: Context): ComponentName =
            ComponentName(context, LockboxDeviceAdminReceiver::class.java)

        fun isActive(context: Context): Boolean {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            return dpm.isAdminActive(component(context))
        }
    }

    override fun onEnabled(context: Context, intent: Intent) {
        Log.i(TAG, "Uninstall protection enabled")
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        "Turning this off removes Lockbox uninstall protection. Anyone with your " +
            "phone could then uninstall Lockbox and open your locked apps."

    override fun onDisabled(context: Context, intent: Intent) {
        Log.w(TAG, "Uninstall protection disabled")
        // Audit trail: the owner can see when protection was removed.
        IntruderRecorder.record(
            context = context,
            lifecycleOwner = null,
            packageName = context.packageName,
            reason = IntruderLogStore.REASON_ADMIN_DISABLED,
            capturePhoto = false,
        )
    }
}
