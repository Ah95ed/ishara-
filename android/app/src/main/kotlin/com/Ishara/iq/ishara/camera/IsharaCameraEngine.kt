package com.Ishara.iq.ishara.camera

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log
import android.util.Size
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * محرك الكاميرا الأصلي (IsharaCameraEngine)
 * يدير دورة حياة CameraX كاملة، واستخراج الإطارات بـ ImageAnalysis،
 * وتغذية الـ PreviewView المباشر على الشاشة بدون تحويل بيانات إلى Dart.
 */
class IsharaCameraEngine(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val onFrame: (ImageProxy, Long) -> Unit
) {

    companion object {
        private const val TAG = "IsharaCameraEngine"
    }

    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var preview: Preview? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var currentPreviewView: PreviewView? = null

    // خيط معالجة الكاميرا المستقل
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    val probe = CameraCapabilityProbe(context)
    val analyzer = CameraFrameAnalyzer(requestedFps = 30, onFrameReceived = onFrame)

    var isFrontCamera: Boolean = true
        private set

    var currentProfile: CameraProfile? = null
        private set

    var isRunning: Boolean = false
        private set

    /**
     * بدء تشغيل الكاميرا بالعدسة المحددة
     */
    fun startCamera(
        previewView: PreviewView?,
        useFrontCamera: Boolean = true,
        onInitialized: ((CameraProfile?) -> Unit)? = null
    ) {
        this.currentPreviewView = previewView
        this.isFrontCamera = useFrontCamera

        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                bindCameraUseCases()
                isRunning = true
                onInitialized?.invoke(currentProfile)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start camera: ${e.message}", e)
                onInitialized?.invoke(null)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    /**
     * تبديل العدسة (Front <-> Back)
     * يعيد فحص القدرات، وتصفير الـ baseline و الـ metrics.
     */
    fun switchCamera(onComplete: ((CameraProfile?) -> Unit)? = null) {
        isFrontCamera = !isFrontCamera
        analyzer.resetMetrics()
        bindCameraUseCases()
        onComplete?.invoke(currentProfile)
    }

    /**
     * ربط استخدامات الكاميرا (Preview + ImageAnalysis)
     */
    @OptIn(ExperimentalCamera2Interop::class)
    @SuppressLint("UnsafeOptInUsageError")
    private fun bindCameraUseCases() {
        val provider = cameraProvider ?: return
        provider.unbindAll()

        // 1. فحص قدرات العدسة المختارة
        val profiles = probe.probeAllCameras()
        val lensFacing = if (isFrontCamera) CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
        val matchedProfile = profiles.values.find {
            if (isFrontCamera) it.isFrontCamera else !it.isFrontCamera
        }
        currentProfile = matchedProfile

        val selectedRes = matchedProfile?.selectedResolution ?: Size(640, 480)
        val selectedFps = matchedProfile?.selectedFpsRange
        if (selectedFps != null) {
            analyzer.updateRequestedFps(selectedFps.upper)
        }

        Log.i(TAG, "Binding camera: isFront=$isFrontCamera, Res=$selectedRes, FPS=$selectedFps")

        // 2. محدد العدسة
        val cameraSelector = CameraSelector.Builder()
            .requireLensFacing(lensFacing)
            .build()

        // 3. بناء الـ Preview المباشر للواجهة
        val previewBuilder = Preview.Builder()
            .setTargetResolution(selectedRes)
        preview = previewBuilder.build().also {
            currentPreviewView?.let { pView ->
                it.setSurfaceProvider(pView.surfaceProvider)
            }
        }

        // 4. بناء الـ ImageAnalysis مع Latest-Frame-Wins و Camera2 FPS Interop
        val analysisBuilder = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setTargetResolution(selectedRes)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)

        // تطبيق نطاق الـ FPS عبر Camera2Interop إذا كان مدعوماً
        if (selectedFps != null) {
            val camera2Config = Camera2Interop.Extender(analysisBuilder)
            camera2Config.setCaptureRequestOption(
                android.hardware.camera2.CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE,
                selectedFps
            )
        }

        imageAnalysis = analysisBuilder.build().also {
            it.setAnalyzer(cameraExecutor, analyzer)
        }

        // 5. الربط مع دورة الحياة
        try {
            camera = provider.bindToLifecycle(
                lifecycleOwner,
                cameraSelector,
                preview,
                imageAnalysis
            )
            Log.i(TAG, "Camera use cases bound successfully.")
        } catch (e: Exception) {
            Log.e(TAG, "Use case binding failed: ${e.message}", e)
        }
    }

    fun attachPreviewView(previewView: PreviewView) {
        this.currentPreviewView = previewView
        preview?.setSurfaceProvider(previewView.surfaceProvider)
    }

    fun stopCamera() {
        try {
            cameraProvider?.unbindAll()
            isRunning = false
            Log.i(TAG, "Camera stopped.")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping camera: ${e.message}", e)
        }
    }

    fun dispose() {
        stopCamera()
        cameraExecutor.shutdown()
    }
}
