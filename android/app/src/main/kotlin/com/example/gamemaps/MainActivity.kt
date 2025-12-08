package com.example.gamemaps

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import android.graphics.Bitmap
import android.graphics.Bitmap.CompressFormat
import android.view.WindowManager
import android.content.Context.WINDOW_SERVICE
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.Looper
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.gamemaps/screen_capture"
    
    // Media projection variables
    private var mediaProjectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var mediaProjectionResultCode: Int = 0
    private var mediaProjectionData: Intent? = null
    
    // Method channel result callback
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "captureScreen" -> {
                    pendingResult = result
                    captureScreen()
                }
                "captureWindow" -> {
                    // Not supported on Android
                    result.error("NOT_SUPPORTED", "Window capture is not supported on Android", null)
                }
                "getRunningWindows" -> {
                    // Not supported on Android
                    result.success(emptyList<String>())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun captureScreen() {
        mediaProjectionManager = getSystemService(MediaProjectionManager::class.java)
        
        if (mediaProjection == null) {
            // Request media projection permission
            startActivityForResult(
                mediaProjectionManager?.createScreenCaptureIntent(),
                REQUEST_MEDIA_PROJECTION
            )
        } else {
            // Already have permission, capture screen immediately
            performScreenCapture()
        }
    }

    private fun performScreenCapture() {
        if (mediaProjection == null) {
            pendingResult?.error("PERMISSION_DENIED", "Media projection permission not granted", null)
            return
        }

        // Get screen dimensions
        val windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val displayMetrics = resources.displayMetrics
        val width = displayMetrics.widthPixels
        val height = displayMetrics.heightPixels

        try {
            // Create ImageReader to capture screen
            val imageReader = ImageReader.newInstance(width, height, 0x1, 2)
            val virtualDisplay = mediaProjection?.createVirtualDisplay(
                "ScreenCapture",
                width, height, displayMetrics.densityDpi,
                WindowManager.LayoutParams.FLAG_AUTO_BACK_LIGHT,
                imageReader.surface, null, null
            )

            // Wait for the image to be available
            Handler(Looper.getMainLooper()).postDelayed({
                val image = imageReader.acquireLatestImage()
                if (image != null) {
                    val bitmap = imageToBitmap(image)
                    image.close()
                    
                    // Compress bitmap to PNG
                    val stream = ByteArrayOutputStream()
                    bitmap.compress(CompressFormat.PNG, 100, stream)
                    val byteArray = stream.toByteArray()
                    
                    // Cleanup
                    virtualDisplay?.release()
                    imageReader.close()
                    
                    // Return result to Flutter
                    pendingResult?.success(byteArray)
                    pendingResult = null
                } else {
                    virtualDisplay?.release()
                    imageReader.close()
                    pendingResult?.error("CAPTURE_FAILED", "Failed to capture screen", null)
                    pendingResult = null
                }
            }, 100)
        } catch (e: Exception) {
            Log.e("ScreenCapture", "Error capturing screen: ${e.message}")
            pendingResult?.error("CAPTURE_FAILED", e.message, null)
            pendingResult = null
        }
    }

    private fun imageToBitmap(image: Image): Bitmap {
        val planes = image.planes
        val buffer: ByteBuffer = planes[0].buffer
        val pixelStride = planes[0].pixelStride
        val rowStride = planes[0].rowStride
        val rowPadding = rowStride - pixelStride * image.width

        // Create bitmap
        val bitmap = Bitmap.createBitmap(
            image.width + rowPadding / pixelStride, image.height, Bitmap.Config.ARGB_8888
        )
        bitmap.copyPixelsFromBuffer(buffer)
        
        // Crop the bitmap to remove padding
        return Bitmap.createBitmap(
            bitmap, 0, 0, image.width, image.height
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            if (resultCode == RESULT_OK) {
                // Save permission result
                mediaProjectionResultCode = resultCode
                mediaProjectionData = data
                
                // Initialize media projection
                mediaProjection = mediaProjectionManager?.getMediaProjection(resultCode, data!!)
                
                // Perform screen capture
                performScreenCapture()
            } else {
                // Permission denied
                pendingResult?.error("PERMISSION_DENIED", "Media projection permission denied", null)
                pendingResult = null
            }
        }
    }

    companion object {
        private const val REQUEST_MEDIA_PROJECTION = 1001
    }
}
