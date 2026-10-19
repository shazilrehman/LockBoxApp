package com.lockbox.lockbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.concurrent.ConcurrentHashMap

/**
 * Intercepts incoming notifications from locked applications.
 *
 * Flow:
 * 1. Checks incoming [StatusBarNotification] against [LockPreferences].
 * 2. If the app is locked and not currently in an active unlock window,
 *    it encrypts the notification content with AES-256-GCM and persists it in
 *    [EncryptedNotificationStore].
 * 3. Immediately cancels the original notification to hide it from the lock screen
 *    and notification shade.
 * 4. Posts a generic "Notification hidden" placeholder that preserves grouped
 *    hierarchy. Tapping the placeholder launches [LockActivity].
 * 5. Upon successful unlock, [onAppUnlocked] cancels the placeholders, decrypts
 *    the content, and reveals the original notifications.
 */
class LockboxNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "LockboxNotifListener"

        const val CHANNEL_HIDDEN = "lockbox_hidden_notifications"
        const val CHANNEL_REVEALED = "lockbox_revealed_notifications"

        private const val TAG_PREFIX_HIDDEN = "lockbox_hidden_"
        private const val TAG_PREFIX_SUMMARY = "lockbox_summary_"
        private const val TAG_PREFIX_REVEALED = "lockbox_revealed_"

        /**
         * Tracks posted placeholder notification tags and IDs per package
         * so they can be accurately cancelled upon unlock.
         */
        private val activePlaceholders = ConcurrentHashMap<String, MutableSet<Pair<String, Int>>>()

        /**
         * Called when [LockActivity] successfully unlocks [packageName].
         * Cancels all generic placeholders, decrypts stored notifications,
         * and reveals the actual content.
         */
        fun onAppUnlocked(context: Context, packageName: String) {
            val notifManager = NotificationManagerCompat.from(context)

            // 1. Cancel all generic placeholders for this package
            activePlaceholders.remove(packageName)?.forEach { (tag, id) ->
                notifManager.cancel(tag, id)
            }

            // 2. Retrieve, decrypt, and re-post original notifications
            val store = EncryptedNotificationStore(context)
            val records = store.getDecryptedNotificationsForPackage(packageName)
            if (records.isEmpty()) return

            val pm = context.packageManager
            val appLabel = try {
                val ai = pm.getApplicationInfo(packageName, 0)
                pm.getApplicationLabel(ai).toString()
            } catch (_: Exception) {
                packageName
            }

            records.forEach { record ->
                val launchIntent = record.contentIntent ?: pm.getLaunchIntentForPackage(packageName)?.let {
                    PendingIntent.getActivity(
                        context,
                        record.notificationId,
                        it,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                }

                val builder = NotificationCompat.Builder(context, CHANNEL_REVEALED)
                    .setSmallIcon(android.R.drawable.ic_popup_reminder)
                    .setContentTitle(record.title ?: appLabel)
                    .setContentText(record.text ?: "")
                    .setSubText(record.subText)
                    .setContentIntent(launchIntent)
                    .setAutoCancel(true)
                    .setWhen(record.postTime)

                record.bigText?.let {
                    builder.setStyle(NotificationCompat.BigTextStyle().bigText(it))
                }

                if (record.groupKey != null) {
                    builder.setGroup(record.groupKey)
                    builder.setGroupSummary(record.isGroupSummary)
                }

                val revealTag = "$TAG_PREFIX_REVEALED${record.packageName}_${record.tag ?: ""}"
                notifManager.notify(revealTag, record.notificationId, builder.build())
            }

            // 3. Clean up database records
            store.deleteForPackage(packageName)
            Log.d(TAG, "Revealed ${records.size} notifications for $packageName")
        }
    }

    private lateinit var prefs: LockPreferences
    private lateinit var store: EncryptedNotificationStore

    override fun onCreate() {
        super.onCreate()
        prefs = LockPreferences(this)
        store = EncryptedNotificationStore(this)
        createNotificationChannels()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val packageName = sbn.packageName

        // ── Guard 1: Never intercept Lockbox's own notifications ──
        if (packageName == this.packageName) return

        // ── Guard 2: Only intercept packages configured as locked ──
        if (!prefs.isAppLocked(packageName)) return

        // ── Guard 3: If app is currently unlocked within timeout window, allow normal display ──
        if (isAppCurrentlyUnlocked(packageName)) return

        // ── Guard 4: Non-clearable ongoing notifications (e.g. active call) should not be cancelled ──
        if (!sbn.isClearable) return

        val notif = sbn.notification ?: return
        val extras = notif.extras

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()

        val isGroupSummary = (notif.flags and Notification.FLAG_GROUP_SUMMARY) != 0
        val groupKey = sbn.groupKey

        // 1. Store notification encrypted
        store.saveNotification(
            key = sbn.key,
            packageName = packageName,
            notificationId = sbn.id,
            tag = sbn.tag,
            groupKey = groupKey,
            isGroupSummary = isGroupSummary,
            postTime = sbn.postTime,
            title = title,
            text = text,
            subText = subText,
            bigText = bigText,
            contentIntent = notif.contentIntent,
        )

        // 2. Cancel original notification from system tray
        cancelNotification(sbn.key)

        // 3. Post generic placeholder notification
        postGenericPlaceholder(sbn, isGroupSummary, groupKey)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // If placeholder was swiped away by user, clean up corresponding stored record
        if (sbn.packageName == this.packageName) {
            val key = sbn.notification.extras?.getString("original_key")
            if (key != null) {
                store.deleteByKey(key)
            }
        }
    }

    // ──────────────── Placeholder Posting ────────────────

    private fun postGenericPlaceholder(
        sbn: StatusBarNotification,
        isGroupSummary: Boolean,
        groupKey: String?,
    ) {
        val packageName = sbn.packageName
        val appLabel = getAppLabel(packageName)
        val notifManager = NotificationManagerCompat.from(this)

        // Intent to launch LockActivity so tapping the notification prompts to unlock
        val unlockIntent = Intent(this, LockActivity::class.java).apply {
            putExtra(LockActivity.EXTRA_LOCKED_PACKAGE, packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            sbn.id,
            unlockIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        if (groupKey != null) {
            if (isGroupSummary) {
                // Post generic group summary
                val hiddenCount = store.getGroupCount(packageName, groupKey)
                val summaryText = if (hiddenCount > 1) {
                    "$hiddenCount notifications hidden"
                } else {
                    "1 notification hidden"
                }

                val summaryBuilder = NotificationCompat.Builder(this, CHANNEL_HIDDEN)
                    .setSmallIcon(android.R.drawable.ic_lock_lock)
                    .setContentTitle(appLabel)
                    .setContentText(summaryText)
                    .setContentIntent(pendingIntent)
                    .setGroup(groupKey)
                    .setGroupSummary(true)
                    .setAutoCancel(true)

                val summaryTag = "$TAG_PREFIX_SUMMARY${packageName}_$groupKey"
                val summaryId = groupKey.hashCode()

                notifManager.notify(summaryTag, summaryId, summaryBuilder.build())
                trackPlaceholder(packageName, summaryTag, summaryId)
            } else {
                // Post generic child notification
                val childBuilder = NotificationCompat.Builder(this, CHANNEL_HIDDEN)
                    .setSmallIcon(android.R.drawable.ic_lock_lock)
                    .setContentTitle(appLabel)
                    .setContentText("Notification hidden")
                    .setSubText("Locked app")
                    .setContentIntent(pendingIntent)
                    .setGroup(groupKey)
                    .setAutoCancel(true)

                val childTag = "$TAG_PREFIX_HIDDEN${packageName}_${sbn.tag ?: ""}"
                notifManager.notify(childTag, sbn.id, childBuilder.build())
                trackPlaceholder(packageName, childTag, sbn.id)

                // Ensure a group summary placeholder is also posted so the group collapses cleanly
                val count = store.getGroupCount(packageName, groupKey).coerceAtLeast(1)
                val autoSummary = NotificationCompat.Builder(this, CHANNEL_HIDDEN)
                    .setSmallIcon(android.R.drawable.ic_lock_lock)
                    .setContentTitle(appLabel)
                    .setContentText("$count notifications hidden")
                    .setContentIntent(pendingIntent)
                    .setGroup(groupKey)
                    .setGroupSummary(true)
                    .setAutoCancel(true)

                val summaryTag = "$TAG_PREFIX_SUMMARY${packageName}_$groupKey"
                val summaryId = groupKey.hashCode()
                notifManager.notify(summaryTag, summaryId, autoSummary.build())
                trackPlaceholder(packageName, summaryTag, summaryId)
            }
        } else {
            // Standalone (non-grouped) generic notification
            val builder = NotificationCompat.Builder(this, CHANNEL_HIDDEN)
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentTitle(appLabel)
                .setContentText("Notification hidden by Lockbox")
                .setSubText("Tap to unlock")
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)

            val tag = "$TAG_PREFIX_HIDDEN${packageName}_${sbn.tag ?: ""}"
            notifManager.notify(tag, sbn.id, builder.build())
            trackPlaceholder(packageName, tag, sbn.id)
        }
    }

    private fun trackPlaceholder(packageName: String, tag: String, id: Int) {
        val set = activePlaceholders.getOrPut(packageName) { ConcurrentHashMap.newKeySet() }
        set.add(Pair(tag, id))
    }

    private fun isAppCurrentlyUnlocked(packageName: String): Boolean {
        val unlockTime = LockboxAccessibilityService.unlockedApps[packageName] ?: return false
        return when (prefs.getTimeoutMode()) {
            TimeoutMode.IMMEDIATE -> false
            TimeoutMode.SCREEN_OFF -> true
            TimeoutMode.TIMED -> {
                val elapsed = System.currentTimeMillis() - unlockTime
                elapsed < prefs.getTimeoutMinutes() * 60_000L
            }
        }
    }

    private fun getAppLabel(packageName: String): String {
        return try {
            val ai = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(ai).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            packageName
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java) ?: return

            val hiddenChannel = NotificationChannel(
                CHANNEL_HIDDEN,
                "Hidden Notifications",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Placeholder notifications for locked applications"
                setShowBadge(false)
            }

            val revealedChannel = NotificationChannel(
                CHANNEL_REVEALED,
                "Unlocked Notifications",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Notifications revealed after unlocking locked applications"
            }

            nm.createNotificationChannel(hiddenChannel)
            nm.createNotificationChannel(revealedChannel)
        }
    }
}
