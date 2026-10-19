package com.lockbox.lockbox

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Clears the unlocked-app state when the screen turns off.
 *
 * Registered dynamically by [LockboxAccessibilityService] — not declared in
 * the manifest (ACTION_SCREEN_OFF cannot be caught via a static receiver
 * on API 26+).
 */
class ScreenOffReceiver(
    private val onScreenOff: () -> Unit,
) : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == Intent.ACTION_SCREEN_OFF) {
            onScreenOff()
        }
    }
}
