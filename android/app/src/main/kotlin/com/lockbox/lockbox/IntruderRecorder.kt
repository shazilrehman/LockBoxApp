package com.lockbox.lockbox

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner

/**
 * Records failed authentication attempts and, only when the owner has given
 * explicit consent AND granted CAMERA, captures one front-camera photo.
 *
 * Capture uses CameraX ImageCapture bound to the calling activity's lifecycle
 * (no preview surface). Android shows its camera privacy indicator while active.
 */
object IntruderRecorder {

    private const val TAG = "IntruderRecorder"

    fun record(
        context: Context,
        lifecycleOwner: LifecycleOwner?,
        packageName: String,
        reason: String,
        capturePhoto: Boolean,
    ) {
        val store = IntruderLogStore(context)
        val label = appLabel(context, packageName)
        val id = store.addEntry(packageName, label, reason)
        if (id < 0) return

        MainActivity.eventStreamHandler?.sendEvent(
            mapOf(
                "packageName" to packageName,
                "eventType" to "intruder_attempt",
                "timestamp" to System.currentTimeMillis(),
            )
        )

        if (!capturePhoto || lifecycleOwner == null) return
        if (!canCapture(context)) return

        captureFrontPhoto(context, lifecycleOwner) { bytes ->
            store.attachPhoto(id, bytes)
        }
    }

    /** Consent flag AND runtime CAMERA permission are both required. */
    fun canCapture(context: Context): Boolean {
        val consent = LockPreferences(context).isIntruderPhotoConsentGiven()
        val granted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.CAMERA,
        ) == PackageManager.PERMISSION_GRANTED
        return consent && granted
    }

    private fun captureFrontPhoto(
        context: Context,
        owner: LifecycleOwner,
        onCaptured: (ByteArray) -> Unit,
    ) {
        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            val provider = try {
                providerFuture.get()
            } catch (e: Exception) {
                Log.w(TAG, "Camera provider unavailable: ${e.message}")
                return@addListener
            }

            val selector = CameraSelector.DEFAULT_FRONT_CAMERA
            if (!provider.hasCamera(selector)) {
                Log.d(TAG, "No front camera")
                return@addListener
            }

            val imageCapture = ImageCapture.Builder()
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                .build()

            try {
                provider.bindToLifecycle(owner, selector, imageCapture)
            } catch (e: Exception) {
                Log.w(TAG, "bindToLifecycle failed: ${e.message}")
                return@addListener
            }

            imageCapture.takePicture(
                ContextCompat.getMainExecutor(context),
                object : ImageCapture.OnImageCapturedCallback() {
                    override fun onCaptureSuccess(image: ImageProxy) {
                        try {
                            // Default ImageCapture output format is JPEG (EXIF orientation preserved).
                            val buffer = image.planes[0].buffer
                            val bytes = ByteArray(buffer.remaining()).also { buffer.get(it) }
                            onCaptured(bytes)
                        } finally {
                            image.close()
                            provider.unbind(imageCapture)
                        }
                    }

                    override fun onError(exception: ImageCaptureException) {
                        Log.w(TAG, "Capture failed: ${exception.message}")
                        provider.unbind(imageCapture)
                    }
                },
            )
        }, ContextCompat.getMainExecutor(context))
    }

    private fun appLabel(context: Context, packageName: String): String? = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
    } catch (_: Exception) {
        null
    }
}
