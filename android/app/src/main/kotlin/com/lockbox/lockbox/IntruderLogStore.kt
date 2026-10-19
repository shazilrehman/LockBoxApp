package com.lockbox.lockbox

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.io.File

/**
 * Persistent intruder log.
 *
 * Each row = one failed authentication attempt (time + package + reason).
 * Photos are optional, captured only with explicit owner consent, and stored
 * as AES-256-GCM encrypted files in app-private storage (never uploaded).
 */
class IntruderLogStore(private val context: Context) : SQLiteOpenHelper(
    context.applicationContext,
    DATABASE_NAME,
    null,
    DATABASE_VERSION,
) {

    companion object {
        private const val TAG = "IntruderLogStore"
        private const val DATABASE_NAME = "lockbox_intruder_log.db"
        private const val DATABASE_VERSION = 1
        private const val TABLE = "intruder_log"
        private const val PHOTO_DIR = "intruder_photos"

        /** Oldest entries (and their photos) are pruned beyond this count. */
        const val MAX_ENTRIES = 200

        const val REASON_WRONG_PIN = "wrong_pin"
        const val REASON_UNINSTALL_PROTECTION = "uninstall_protection"
        const val REASON_ADMIN_DISABLED = "admin_disabled"
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                package_name TEXT NOT NULL,
                app_label TEXT,
                reason TEXT NOT NULL,
                photo_file TEXT
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS $TABLE")
        onCreate(db)
    }

    /** Inserts an entry and returns its row id (or -1 on failure). */
    fun addEntry(packageName: String, appLabel: String?, reason: String): Long {
        return try {
            val values = ContentValues().apply {
                put("timestamp", System.currentTimeMillis())
                put("package_name", packageName)
                put("app_label", appLabel)
                put("reason", reason)
            }
            val id = writableDatabase.insert(TABLE, null, values)
            prune()
            id
        } catch (e: Exception) {
            Log.e(TAG, "addEntry failed: ${e.message}", e)
            -1
        }
    }

    /** Encrypts [jpegBytes] to disk and links the file to entry [id]. */
    fun attachPhoto(id: Long, jpegBytes: ByteArray) {
        try {
            val dir = File(context.filesDir, PHOTO_DIR).apply { mkdirs() }
            val file = File(dir, "$id.enc")
            file.writeBytes(NotificationCryptoHelper.encryptBytes(jpegBytes))
            val values = ContentValues().apply { put("photo_file", file.name) }
            writableDatabase.update(TABLE, values, "id = ?", arrayOf(id.toString()))
        } catch (e: Exception) {
            Log.e(TAG, "attachPhoto failed: ${e.message}", e)
        }
    }

    /** Returns all entries, newest first. */
    fun getEntries(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        readableDatabase.query(TABLE, null, null, null, null, null, "timestamp DESC").use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(c.getColumnIndexOrThrow("id")),
                        "timestamp" to c.getLong(c.getColumnIndexOrThrow("timestamp")),
                        "packageName" to c.getString(c.getColumnIndexOrThrow("package_name")),
                        "appLabel" to c.getString(c.getColumnIndexOrThrow("app_label")),
                        "reason" to c.getString(c.getColumnIndexOrThrow("reason")),
                        "hasPhoto" to !c.isNull(c.getColumnIndexOrThrow("photo_file")),
                    )
                )
            }
        }
        return out
    }

    /** Decrypted JPEG bytes for entry [id], or null if none/undecryptable. */
    fun getPhoto(id: Long): ByteArray? {
        val name = photoFileName(id) ?: return null
        val file = File(File(context.filesDir, PHOTO_DIR), name)
        if (!file.exists()) return null
        return try {
            NotificationCryptoHelper.decryptBytes(file.readBytes())
        } catch (e: Exception) {
            Log.w(TAG, "Photo decrypt failed for $id: ${e.message}")
            null
        }
    }

    fun deleteEntry(id: Long) {
        deletePhotoFile(photoFileName(id))
        writableDatabase.delete(TABLE, "id = ?", arrayOf(id.toString()))
    }

    fun clearAll() {
        File(context.filesDir, PHOTO_DIR).deleteRecursively()
        writableDatabase.delete(TABLE, null, null)
    }

    /** Deletes stored photos only (used when consent is withdrawn). */
    fun deleteAllPhotos() {
        File(context.filesDir, PHOTO_DIR).deleteRecursively()
        val values = ContentValues().apply { putNull("photo_file") }
        writableDatabase.update(TABLE, values, null, null)
    }

    // ───────────────────────── Internals ─────────────────────────

    private fun photoFileName(id: Long): String? =
        readableDatabase.query(
            TABLE, arrayOf("photo_file"), "id = ?", arrayOf(id.toString()),
            null, null, null,
        ).use { c -> if (c.moveToFirst() && !c.isNull(0)) c.getString(0) else null }

    private fun deletePhotoFile(name: String?) {
        if (name == null) return
        File(File(context.filesDir, PHOTO_DIR), name).delete()
    }

    private fun prune() {
        val db = writableDatabase
        db.rawQuery(
            "SELECT id, photo_file FROM $TABLE ORDER BY timestamp DESC LIMIT -1 OFFSET $MAX_ENTRIES",
            null,
        ).use { c ->
            while (c.moveToNext()) {
                deletePhotoFile(if (c.isNull(1)) null else c.getString(1))
                db.delete(TABLE, "id = ?", arrayOf(c.getLong(0).toString()))
            }
        }
    }
}
