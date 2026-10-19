package com.lockbox.lockbox

import android.content.Context
import android.content.SharedPreferences

/**
 * Single source of truth for the locked-app set and re-lock timeout policy.
 * Used by both [LockboxAccessibilityService] and [LockboxMethodCallHandler].
 */
class LockPreferences(context: Context) {

    companion object {
        private const val PREFS_NAME = "lockbox_prefs"
        private const val KEY_LOCKED_APPS = "locked_apps"
        private const val KEY_TIMEOUT_MODE = "timeout_mode"
        private const val KEY_TIMEOUT_MINUTES = "timeout_minutes"
        private const val DEFAULT_TIMEOUT_MINUTES = 1
        private const val KEY_PHOTO_CONSENT = "intruder_photo_consent"
        private const val KEY_PHOTO_CONSENT_AT = "intruder_photo_consent_at"
        private const val KEY_PROTECTION_SERVICE = "protection_service_enabled"
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // ─────────────────── Locked apps ─────────────────────

    fun getLockedApps(): Set<String> =
        prefs.getStringSet(KEY_LOCKED_APPS, emptySet()) ?: emptySet()

    fun setLockedApps(apps: Set<String>) {
        prefs.edit().putStringSet(KEY_LOCKED_APPS, apps).apply()
    }

    fun isAppLocked(packageName: String): Boolean =
        getLockedApps().contains(packageName)

    // ────────────────── Timeout policy ───────────────────

    fun getTimeoutMode(): TimeoutMode {
        val raw = prefs.getString(KEY_TIMEOUT_MODE, TimeoutMode.IMMEDIATE.name)
        return try {
            TimeoutMode.valueOf(raw ?: TimeoutMode.IMMEDIATE.name)
        } catch (_: IllegalArgumentException) {
            TimeoutMode.IMMEDIATE
        }
    }

    fun setTimeoutMode(mode: TimeoutMode) {
        prefs.edit().putString(KEY_TIMEOUT_MODE, mode.name).apply()
    }

    fun getTimeoutMinutes(): Int =
        prefs.getInt(KEY_TIMEOUT_MINUTES, DEFAULT_TIMEOUT_MINUTES)

    fun setTimeoutMinutes(minutes: Int) {
        prefs.edit().putInt(KEY_TIMEOUT_MINUTES, minutes.coerceAtLeast(1)).apply()
    }

    // ──────────────── Intruder photo consent ─────────────

    fun isIntruderPhotoConsentGiven(): Boolean =
        prefs.getBoolean(KEY_PHOTO_CONSENT, false)

    /** Epoch ms when consent was given (0 if never/withdrawn). */
    fun getIntruderPhotoConsentAt(): Long =
        prefs.getLong(KEY_PHOTO_CONSENT_AT, 0L)

    fun setIntruderPhotoConsent(given: Boolean) {
        prefs.edit()
            .putBoolean(KEY_PHOTO_CONSENT, given)
            .putLong(KEY_PHOTO_CONSENT_AT, if (given) System.currentTimeMillis() else 0L)
            .apply()
    }

    // ─────────────── Protection service opt-in ───────────

    fun isProtectionServiceEnabled(): Boolean =
        prefs.getBoolean(KEY_PROTECTION_SERVICE, false)

    fun setProtectionServiceEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_PROTECTION_SERVICE, enabled).apply()
    }
}

/**
 * Re-lock timeout modes.
 *
 * - [IMMEDIATE] — every foreground switch requires auth.
 * - [SCREEN_OFF] — unlocked until the screen turns off.
 * - [TIMED] — unlocked for N minutes (see [LockPreferences.getTimeoutMinutes]).
 */
enum class TimeoutMode {
    IMMEDIATE,
    SCREEN_OFF,
    TIMED,
}
