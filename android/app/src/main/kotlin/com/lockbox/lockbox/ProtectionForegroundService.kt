package com.lockbox.lockbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Persistent foreground service that acts as Lockbox's watchdog.
 *
 * Why it exists: once the user (or the OEM) disables the Accessibility service,
 * nothing else in Lockbox is running to notice. This service:
 *  - observes `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES` for instant detection,
 *  - re-checks every [CHECK_INTERVAL_MS] to catch "enabled but not running" (crash/kill),
 *  - posts a high-priority warning notification while the lock engine is down.
 *
 * FGS type: `specialUse` (Android 14+), justified in the manifest property.
 */
class ProtectionForegroundService : Service() {

    companion object {
        private const val TAG = "ProtectionFGS"

        const val CHANNEL_STATUS = "lockbox_protection_status"
        const val CHANNEL_ALERTS = "lockbox_health_alerts"
        private const val NOTIF_ID_STATUS = 7001
        private const val NOTIF_ID_ALERT = 7002
        private const val CHECK_INTERVAL_MS = 15 * 60 * 1000L

        @Volatile
        var isRunning: Boolean = false
            private set

        /** Starts the service; safe to call when already running. */
        fun start(context: Context): Boolean = try {
            ContextCompat.startForegroundService(
                context, Intent(context, ProtectionForegroundService::class.java),
            )
            true
        } catch (e: Exception) {
            // ForegroundServiceStartNotAllowedException on API 31+ if started from background
            Log.w(TAG, "Could not start protection service: ${e.message}")
            false
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ProtectionForegroundService::class.java))
        }

        /**
         * Triggers an immediate re-check from other in-process components
         * (e.g. the a11y service connecting/dying). Uses the live instance
         * rather than startForegroundService, which may be blocked from background.
         */
        fun requestHealthCheck() {
            instance?.let { svc -> svc.handler.post { svc.runHealthCheck() } }
        }

        @Volatile
        private var instance: ProtectionForegroundService? = null
    }

    private val handler = Handler(Looper.getMainLooper())

    private val periodicCheck = object : Runnable {
        override fun run() {
            runHealthCheck()
            handler.postDelayed(this, CHECK_INTERVAL_MS)
        }
    }

    private val accessibilityObserver = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) {
            // Give the system a moment to bind/unbind the service before checking.
            handler.postDelayed({ runHealthCheck() }, 1_500)
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannels()
        contentResolver.registerContentObserver(
            Settings.Secure.getUriFor(Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES),
            false,
            accessibilityObserver,
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }
        ServiceCompat.startForeground(this, NOTIF_ID_STATUS, buildStatusNotification(), type)
        isRunning = true

        handler.removeCallbacks(periodicCheck)
        handler.post(periodicCheck)
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        instance = null
        handler.removeCallbacksAndMessages(null)
        contentResolver.unregisterContentObserver(accessibilityObserver)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ──────────────────────── Health check ────────────────────────

    private fun runHealthCheck() {
        val engineDown = HealthChecker.isLockEngineDown(this)
        val nm = NotificationManagerCompat.from(this)

        if (engineDown && HealthChecker.isPostNotificationsGranted(this)) {
            nm.notify(NOTIF_ID_ALERT, buildAlertNotification())
        } else if (!engineDown) {
            nm.cancel(NOTIF_ID_ALERT)
        }

        // Refresh the ongoing status text.
        if (HealthChecker.isPostNotificationsGranted(this)) {
            nm.notify(NOTIF_ID_STATUS, buildStatusNotification())
        }

        MainActivity.eventStreamHandler?.sendEvent(
            mapOf(
                "packageName" to "",
                "eventType" to "health_changed",
                "timestamp" to System.currentTimeMillis(),
            )
        )
        Log.d(TAG, "Health check: engineDown=$engineDown")
    }

    // ─────────────────────── Notifications ────────────────────────

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        this, 0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun buildStatusNotification(): Notification {
        val count = LockPreferences(this).getLockedApps().size
        val text = if (HealthChecker.isLockEngineDown(this)) {
            "Protection paused — Accessibility service is off"
        } else {
            "Protecting $count app${if (count == 1) "" else "s"}"
        }
        return NotificationCompat.Builder(this, CHANNEL_STATUS)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("Lockbox")
            .setContentText(text)
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun buildAlertNotification(): Notification {
        val fixIntent = PendingIntent.getActivity(
            this, 1,
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ALERTS)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle("Your apps are not locked")
            .setContentText("Lockbox's Accessibility service is disabled. Tap to turn it back on.")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "Lockbox's Accessibility service is disabled or was stopped by the system, " +
                        "so locked apps can be opened without your PIN. Tap to turn it back on."
                )
            )
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ERROR)
            .setContentIntent(fixIntent)
            .addAction(0, "Turn on", fixIntent)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .build()
    }

    private fun createChannels() {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_STATUS, "Protection status", NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "Ongoing notification while Lockbox protection is running"
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ALERTS, "Protection alerts", NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Warns you when app locking stops working"
            }
        )
    }
}
