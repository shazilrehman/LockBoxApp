package com.lockbox.lockbox

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Handles every MethodChannel call from the Dart side.
 *
 * Channel name: `com.lockbox/methods`
 */
class LockboxMethodCallHandler(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    private val prefs = LockPreferences(context)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInstalledApps" -> handleGetInstalledApps(call, result)
            "setLockedApps" -> handleSetLockedApps(call, result)
            "isAccessibilityEnabled" -> handleIsAccessibilityEnabled(result)
            "openAccessibilitySettings" -> handleOpenAccessibilitySettings(result)
            "isNotificationAccessEnabled" -> handleIsNotificationAccessEnabled(result)
            "openNotificationSettings" -> handleOpenNotificationSettings(result)
            "isOverlayPermissionGranted" -> handleIsOverlayPermissionGranted(result)
            "openOverlaySettings" -> handleOpenOverlaySettings(result)
            "isBatteryOptimizationIgnored" -> handleIsBatteryOptimizationIgnored(result)
            "requestBatteryOptimization" -> handleRequestBatteryOptimization(result)
            "isSamsungDevice" -> handleIsSamsungDevice(result)
            "setRelockPolicy" -> handleSetRelockPolicy(call, result)
            "getRelockPolicy" -> handleGetRelockPolicy(result)
            else -> result.notImplemented()
        }
    }

    // ─────────────────── getInstalledApps ────────────────────

    private fun handleGetInstalledApps(call: MethodCall, result: MethodChannel.Result) {
        val includeSystemApps = call.argument<Boolean>("includeSystemApps") ?: false

        try {
            val pm: PackageManager = context.packageManager
            val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)

            val mapped = apps
                .filter { app ->
                    if (includeSystemApps) true
                    else (app.flags and ApplicationInfo.FLAG_SYSTEM) == 0
                }
                .map { app ->
                    mapOf(
                        "packageName" to app.packageName,
                        "appName" to (pm.getApplicationLabel(app)?.toString() ?: app.packageName),
                        "isSystemApp" to ((app.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                    )
                }
                .sortedBy { it["appName"] as String }

            result.success(mapped)
        } catch (e: Exception) {
            result.error("GET_APPS_ERROR", e.localizedMessage, null)
        }
    }

    // ─────────────────── setLockedApps ───────────────────────

    private fun handleSetLockedApps(call: MethodCall, result: MethodChannel.Result) {
        val packageNames = call.argument<List<String>>("packageNames")
        if (packageNames == null) {
            result.error("INVALID_ARGS", "packageNames list is required", null)
            return
        }

        try {
            prefs.setLockedApps(packageNames.toSet())
            result.success(true)
        } catch (e: Exception) {
            result.error("SET_APPS_ERROR", e.localizedMessage, null)
        }
    }

    // ─────────────── isAccessibilityEnabled ──────────────────

    private fun handleIsAccessibilityEnabled(result: MethodChannel.Result) {
        try {
            val expectedComponent = ComponentName(context, LockboxAccessibilityService::class.java)
            val enabledServices: String = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: ""

            val colonSplitter = TextUtils.SimpleStringSplitter(':')
            colonSplitter.setString(enabledServices)

            var found = false
            while (colonSplitter.hasNext()) {
                val component = ComponentName.unflattenFromString(colonSplitter.next())
                if (component != null && component == expectedComponent) {
                    found = true
                    break
                }
            }

            result.success(found)
        } catch (e: Exception) {
            result.error("ACCESSIBILITY_CHECK_ERROR", e.localizedMessage, null)
        }
    }

    // ────────────── openAccessibilitySettings ────────────────

    private fun handleOpenAccessibilitySettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            result.error("OPEN_SETTINGS_ERROR", e.localizedMessage, null)
        }
    }

    // ─────────── isNotificationAccessEnabled ─────────────────

    private fun handleIsNotificationAccessEnabled(result: MethodChannel.Result) {
        try {
            val enabledListeners: String = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ) ?: ""

            val packageName = context.packageName
            val enabled = enabledListeners.contains(packageName)

            result.success(enabled)
        } catch (e: Exception) {
            result.error("NOTIFICATION_CHECK_ERROR", e.localizedMessage, null)
        }
    }

    // ──────────── openNotificationSettings ───────────────────

    private fun handleOpenNotificationSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            result.error("OPEN_NOTIF_SETTINGS_ERROR", e.localizedMessage, null)
        }
    }

    // ──────────── isOverlayPermissionGranted ─────────────────

    private fun handleIsOverlayPermissionGranted(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                result.success(Settings.canDrawOverlays(context))
            } else {
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("OVERLAY_CHECK_ERROR", e.localizedMessage, null)
        }
    }

    // ─────────────── openOverlaySettings ─────────────────────

    private fun handleOpenOverlaySettings(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${context.packageName}"),
                ).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            }
            result.success(null)
        } catch (e: Exception) {
            try {
                val fallbackIntent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(fallbackIntent)
                result.success(null)
            } catch (e2: Exception) {
                result.error("OPEN_OVERLAY_SETTINGS_ERROR", e2.localizedMessage, null)
            }
        }
    }

    // ────────── isBatteryOptimizationIgnored ─────────────────

    private fun handleIsBatteryOptimizationIgnored(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                result.success(pm?.isIgnoringBatteryOptimizations(context.packageName) ?: false)
            } else {
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("BATTERY_CHECK_ERROR", e.localizedMessage, null)
        }
    }

    // ─────────── requestBatteryOptimization ──────────────────

    private fun handleRequestBatteryOptimization(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${context.packageName}"),
                ).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            }
            result.success(null)
        } catch (e: Exception) {
            try {
                val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(fallback)
                result.success(null)
            } catch (e2: Exception) {
                result.error("BATTERY_REQUEST_ERROR", e2.localizedMessage, null)
            }
        }
    }

    // ───────────────── isSamsungDevice ───────────────────────

    private fun handleIsSamsungDevice(result: MethodChannel.Result) {
        val isSamsung = Build.MANUFACTURER.equals("samsung", ignoreCase = true)
        result.success(isSamsung)
    }

    // ────────────────── setRelockPolicy ──────────────────────

    private fun handleSetRelockPolicy(call: MethodCall, result: MethodChannel.Result) {
        val modeStr = call.argument<String>("mode")
        val minutes = call.argument<Int>("minutes")

        if (modeStr == null) {
            result.error("INVALID_ARGS", "'mode' is required", null)
            return
        }

        try {
            val mode = TimeoutMode.valueOf(modeStr.uppercase())
            prefs.setTimeoutMode(mode)
            if (mode == TimeoutMode.TIMED && minutes != null) {
                prefs.setTimeoutMinutes(minutes)
            }
            result.success(true)
        } catch (e: IllegalArgumentException) {
            result.error("INVALID_ARGS", "Unknown mode: $modeStr. Use IMMEDIATE, SCREEN_OFF, or TIMED.", null)
        } catch (e: Exception) {
            result.error("SET_POLICY_ERROR", e.localizedMessage, null)
        }
    }

    // ────────────────── getRelockPolicy ──────────────────────

    private fun handleGetRelockPolicy(result: MethodChannel.Result) {
        try {
            result.success(
                mapOf(
                    "mode" to prefs.getTimeoutMode().name,
                    "minutes" to prefs.getTimeoutMinutes(),
                )
            )
        } catch (e: Exception) {
            result.error("GET_POLICY_ERROR", e.localizedMessage, null)
        }
    }
}
