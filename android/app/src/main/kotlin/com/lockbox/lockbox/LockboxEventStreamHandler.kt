package com.lockbox.lockbox

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * EventChannel stream handler for `com.lockbox/events`.
 *
 * Native code (e.g. the AccessibilityService) posts [LockEvent]-like maps
 * through [sendEvent]. The handler forwards them to the Dart side.
 */
class LockboxEventStreamHandler : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /**
     * Call from any thread — the event is posted to the main looper
     * so the EventSink is used safely.
     */
    fun sendEvent(event: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }

    /** Send an error to the Dart side. */
    fun sendError(code: String, message: String?, details: Any? = null) {
        mainHandler.post {
            eventSink?.error(code, message, details)
        }
    }
}
