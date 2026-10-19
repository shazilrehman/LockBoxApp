package com.lockbox.lockbox

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.lockbox/methods"
        private const val EVENT_CHANNEL = "com.lockbox/events"

        /**
         * Global reference so the AccessibilityService can push events
         * back to the Dart side without holding an Activity reference.
         */
        var eventStreamHandler: LockboxEventStreamHandler? = null
            private set
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── MethodChannel ────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler(LockboxMethodCallHandler(this))

        // ── EventChannel ─────────────────────────────────────
        val streamHandler = LockboxEventStreamHandler()
        eventStreamHandler = streamHandler

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(streamHandler)
    }

    override fun onDestroy() {
        eventStreamHandler = null
        super.onDestroy()
    }
}
