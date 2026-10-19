package com.lockbox.lockbox

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restarts the protection watchdog after reboot and after app updates
 * (an update kills the running foreground service).
 *
 * Only acts if the user previously enabled the protection service.
 * BOOT_COMPLETED is an allowed context for starting a `specialUse` FGS,
 * including on Android 15 (which restricts other FGS types from boot).
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return

        // In-memory unlock grants never survive a reboot, but be explicit.
        LockboxAccessibilityService.clearAllUnlocked()

        if (!LockPreferences(context).isProtectionServiceEnabled()) {
            Log.d("LockboxBoot", "$action: protection service not enabled, skipping")
            return
        }
        val started = ProtectionForegroundService.start(context)
        Log.i("LockboxBoot", "$action: protection service started=$started")
    }
}
