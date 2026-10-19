package com.lockbox.lockbox

import android.app.Application
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Custom [Application] that pre-warms a second [FlutterEngine]
 * for the lock screen.
 *
 * The engine executes the `lockMain` Dart entrypoint immediately at
 * process start so that [LockActivity] can attach with near-zero
 * latency when the accessibility service intercepts a locked app.
 */
class LockboxApplication : Application() {

    companion object {
        const val LOCK_ENGINE_ID = "lock_engine"
    }

    override fun onCreate() {
        super.onCreate()
        preWarmLockEngine()
    }

    private fun preWarmLockEngine() {
        val flutterLoader = FlutterInjector.instance().flutterLoader()
        flutterLoader.startInitialization(this)
        flutterLoader.ensureInitializationComplete(this, null)

        val lockEngine = FlutterEngine(this)

        lockEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                flutterLoader.findAppBundlePath(),
                "lockMain",
            )
        )

        FlutterEngineCache.getInstance().put(LOCK_ENGINE_ID, lockEngine)
    }
}
