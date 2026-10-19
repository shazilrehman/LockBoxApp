package com.lockbox.lockbox

import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.util.concurrent.ConcurrentHashMap

data class DecryptedNotificationRecord(
    val key: String,
    val packageName: String,
    val notificationId: Int,
    val tag: String?,
    val groupKey: String?,
    val isGroupSummary: Boolean,
    val postTime: Long,
    val title: String?,
    val text: String?,
    val subText: String?,
    val bigText: String?,
    val contentIntent: PendingIntent?,
)

/**
 * SQLite-backed persistent store for notifications intercepted from locked apps.
 * All text content is encrypted with AES-256-GCM via [NotificationCryptoHelper]
 * before hitting disk.
 */
class EncryptedNotificationStore(context: Context) : SQLiteOpenHelper(
    context,
    DATABASE_NAME,
    null,
    DATABASE_VERSION,
) {

    companion object {
        private const val TAG = "NotifStore"
        private const val DATABASE_NAME = "lockbox_hidden_notifications.db"
        private const val DATABASE_VERSION = 1

        private const val TABLE_NAME = "hidden_notifications"
        private const val COL_KEY = "key"
        private const val COL_PACKAGE_NAME = "package_name"
        private const val COL_NOTIF_ID = "notification_id"
        private const val COL_TAG = "tag"
        private const val COL_GROUP_KEY = "group_key"
        private const val COL_IS_GROUP_SUMMARY = "is_group_summary"
        private const val COL_POST_TIME = "post_time"
        private const val COL_ENC_TITLE = "enc_title"
        private const val COL_ENC_TEXT = "enc_text"
        private const val COL_ENC_SUB_TEXT = "enc_sub_text"
        private const val COL_ENC_BIG_TEXT = "enc_big_text"

        // In-memory cache for PendingIntents associated with active notifications
        private val pendingIntentCache = ConcurrentHashMap<String, PendingIntent>()
    }

    override fun onCreate(db: SQLiteDatabase) {
        val createSql = """
            CREATE TABLE $TABLE_NAME (
                $COL_KEY TEXT PRIMARY KEY,
                $COL_PACKAGE_NAME TEXT NOT NULL,
                $COL_NOTIF_ID INTEGER NOT NULL,
                $COL_TAG TEXT,
                $COL_GROUP_KEY TEXT,
                $COL_IS_GROUP_SUMMARY INTEGER NOT NULL,
                $COL_POST_TIME INTEGER NOT NULL,
                $COL_ENC_TITLE TEXT,
                $COL_ENC_TEXT TEXT,
                $COL_ENC_SUB_TEXT TEXT,
                $COL_ENC_BIG_TEXT TEXT
            )
        """.trimIndent()
        db.execSQL(createSql)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS $TABLE_NAME")
        onCreate(db)
    }

    /**
     * Encrypts and stores the notification details.
     */
    fun saveNotification(
        key: String,
        packageName: String,
        notificationId: Int,
        tag: String?,
        groupKey: String?,
        isGroupSummary: Boolean,
        postTime: Long,
        title: String?,
        text: String?,
        subText: String?,
        bigText: String?,
        contentIntent: PendingIntent?,
    ) {
        try {
            contentIntent?.let { pendingIntentCache[key] = it }

            val encTitle = title?.let { NotificationCryptoHelper.encrypt(it) }
            val encText = text?.let { NotificationCryptoHelper.encrypt(it) }
            val encSubText = subText?.let { NotificationCryptoHelper.encrypt(it) }
            val encBigText = bigText?.let { NotificationCryptoHelper.encrypt(it) }

            val values = ContentValues().apply {
                put(COL_KEY, key)
                put(COL_PACKAGE_NAME, packageName)
                put(COL_NOTIF_ID, notificationId)
                put(COL_TAG, tag)
                put(COL_GROUP_KEY, groupKey)
                put(COL_IS_GROUP_SUMMARY, if (isGroupSummary) 1 else 0)
                put(COL_POST_TIME, postTime)
                put(COL_ENC_TITLE, encTitle)
                put(COL_ENC_TEXT, encText)
                put(COL_ENC_SUB_TEXT, encSubText)
                put(COL_ENC_BIG_TEXT, encBigText)
            }

            writableDatabase.insertWithOnConflict(
                TABLE_NAME,
                null,
                values,
                SQLiteDatabase.CONFLICT_REPLACE,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to store encrypted notification for $packageName: ${e.message}", e)
        }
    }

    /**
     * Retrieves and decrypts all notifications stored for [packageName].
     */
    fun getDecryptedNotificationsForPackage(packageName: String): List<DecryptedNotificationRecord> {
        val records = mutableListOf<DecryptedNotificationRecord>()
        val cursor = readableDatabase.query(
            TABLE_NAME,
            null,
            "$COL_PACKAGE_NAME = ?",
            arrayOf(packageName),
            null,
            null,
            "$COL_POST_TIME ASC",
        )

        cursor.use {
            while (it.moveToNext()) {
                val key = it.getString(it.getColumnIndexOrThrow(COL_KEY))
                val notifId = it.getInt(it.getColumnIndexOrThrow(COL_NOTIF_ID))
                val tag = it.getString(it.getColumnIndexOrThrow(COL_TAG))
                val groupKey = it.getString(it.getColumnIndexOrThrow(COL_GROUP_KEY))
                val isGroupSummary = it.getInt(it.getColumnIndexOrThrow(COL_IS_GROUP_SUMMARY)) == 1
                val postTime = it.getLong(it.getColumnIndexOrThrow(COL_POST_TIME))

                val encTitle = it.getString(it.getColumnIndexOrThrow(COL_ENC_TITLE))
                val encText = it.getString(it.getColumnIndexOrThrow(COL_ENC_TEXT))
                val encSubText = it.getString(it.getColumnIndexOrThrow(COL_ENC_SUB_TEXT))
                val encBigText = it.getString(it.getColumnIndexOrThrow(COL_ENC_BIG_TEXT))

                val title = encTitle?.let { enc -> safeDecrypt(enc) }
                val text = encText?.let { enc -> safeDecrypt(enc) }
                val subText = encSubText?.let { enc -> safeDecrypt(enc) }
                val bigText = encBigText?.let { enc -> safeDecrypt(enc) }

                records.add(
                    DecryptedNotificationRecord(
                        key = key,
                        packageName = packageName,
                        notificationId = notifId,
                        tag = tag,
                        groupKey = groupKey,
                        isGroupSummary = isGroupSummary,
                        postTime = postTime,
                        title = title,
                        text = text,
                        subText = subText,
                        bigText = bigText,
                        contentIntent = pendingIntentCache[key],
                    )
                )
            }
        }
        return records
    }

    /**
     * Returns the count of hidden child notifications currently stored for a group.
     */
    fun getGroupCount(packageName: String, groupKey: String?): Int {
        if (groupKey == null) return 0
        val cursor = readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM $TABLE_NAME WHERE $COL_PACKAGE_NAME = ? AND $COL_GROUP_KEY = ? AND $COL_IS_GROUP_SUMMARY = 0",
            arrayOf(packageName, groupKey),
        )
        return cursor.use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
    }

    /**
     * Deletes all stored records for [packageName] and cleans up cached PendingIntents.
     */
    fun deleteForPackage(packageName: String) {
        try {
            val cursor = readableDatabase.query(
                TABLE_NAME,
                arrayOf(COL_KEY),
                "$COL_PACKAGE_NAME = ?",
                arrayOf(packageName),
                null,
                null,
                null,
            )
            cursor.use {
                while (it.moveToNext()) {
                    val key = it.getString(0)
                    pendingIntentCache.remove(key)
                }
            }
            writableDatabase.delete(TABLE_NAME, "$COL_PACKAGE_NAME = ?", arrayOf(packageName))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete records for $packageName: ${e.message}", e)
        }
    }

    /**
     * Deletes a single notification record by its key.
     */
    fun deleteByKey(key: String) {
        pendingIntentCache.remove(key)
        writableDatabase.delete(TABLE_NAME, "$COL_KEY = ?", arrayOf(key))
    }

    private fun safeDecrypt(encrypted: String): String? {
        return try {
            NotificationCryptoHelper.decrypt(encrypted)
        } catch (e: Exception) {
            Log.w(TAG, "Decryption failure: ${e.message}")
            null
        }
    }
}
