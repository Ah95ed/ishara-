package com.Ishara.iq.ishara.camera

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.util.Range
import android.util.Size
import android.util.Log

/**
 * ملف تعريف قدرات الكاميرا المستقلة (CameraProfile)
 * يخزن قدرات كل عدسة على حدة (Front / Back) دون تعميم أو افتراضات مسبقة.
 */
data class CameraProfile(
    val cameraId: String,
    val lensFacing: Int, // CameraCharacteristics.LENS_FACING_FRONT or LENS_FACING_BACK
    val supportedFpsRanges: List<Range<Int>>,
    val supportedResolutions: List<Size>,
    val selectedFpsRange: Range<Int>,
    val selectedResolution: Size,
    val sensorOrientation: Int
) {
    val isFrontCamera: Boolean get() = lensFacing == CameraCharacteristics.LENS_FACING_FRONT
    val maxSupportedFps: Int get() = supportedFpsRanges.maxOfOrNull { it.upper } ?: 30

    fun toMap(): Map<String, Any> {
        return mapOf(
            "cameraId" to cameraId,
            "lensFacing" to if (isFrontCamera) "FRONT" else "BACK",
            "supportedFpsRanges" to supportedFpsRanges.map { "[${it.lower}, ${it.upper}]" },
            "supportedResolutions" to supportedResolutions.map { "${it.width}x${it.height}" },
            "selectedFps" to "[${selectedFpsRange.lower}, ${selectedFpsRange.upper}]",
            "selectedResolution" to "${selectedResolution.width}x${selectedResolution.height}",
            "sensorOrientation" to sensorOrientation,
            "maxSupportedFps" to maxSupportedFps
        )
    }
}

/**
 * فاحص قدرات الكاميرات الفعلي (CameraCapabilityProbe)
 * يفحص قدرات كل كاميرا حقيقية على الجهاز عبر Camera2 API مباشرة
 * ويسجل الفريمات المدعومة والدقات المتاحة دون افتراض 30 أو 60 فريم.
 */
class CameraCapabilityProbe(private val context: Context) {

    companion object {
        private const val TAG = "CameraCapabilityProbe"
    }

    private val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    /**
     * فحص جميع الكاميرات المتاحة وتوليد تقرير قدرات مستقل لكل كاميرا.
     */
    fun probeAllCameras(): Map<String, CameraProfile> {
        val profiles = mutableMapOf<String, CameraProfile>()

        try {
            val cameraIds = cameraManager.cameraIdList
            Log.d(TAG, "Found ${cameraIds.size} available cameras.")

            for (id in cameraIds) {
                val chars = cameraManager.getCameraCharacteristics(id)
                val facing = chars.get(CameraCharacteristics.LENS_FACING) ?: continue

                // 1. استخراج نطاقات الـ FPS المدعومة
                val fpsRanges = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                    ?.toList() ?: listOf(Range(30, 30))

                // 2. استخراج الدقات المدعومة لصيغة YUV_420_888
                val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                val yuvSizes = map?.getOutputSizes(ImageFormat.YUV_420_888)?.toList()
                    ?: listOf(Size(640, 480))

                // 3. اتجاه المستشعر
                val orientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90

                // 4. اختيار أنسب نطاق FPS ودقة وفق استراتيجية المشروع
                val selectedFps = CameraFpsSelector.selectBestFpsRange(fpsRanges)
                val selectedRes = CameraFpsSelector.selectOptimalResolution(yuvSizes)

                val profile = CameraProfile(
                    cameraId = id,
                    lensFacing = facing,
                    supportedFpsRanges = fpsRanges,
                    supportedResolutions = yuvSizes,
                    selectedFpsRange = selectedFps,
                    selectedResolution = selectedRes,
                    sensorOrientation = orientation
                )

                profiles[id] = profile
                Log.i(TAG, "Probed camera $id (${if (facing == CameraCharacteristics.LENS_FACING_FRONT) "FRONT" else "BACK"}): " +
                        "MaxFPS=${profile.maxSupportedFps}, SelectedFPS=${selectedFps}, SelectedRes=${selectedRes}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error probing cameras: ${e.message}", e)
        }

        return profiles
    }

    /**
     * الحصول على معرف الكاميرا الأمامية أو الخلفية
     */
    fun getCameraIdForLens(isFront: Boolean): String? {
        val targetFacing = if (isFront) CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
        for (id in cameraManager.cameraIdList) {
            val chars = cameraManager.getCameraCharacteristics(id)
            if (chars.get(CameraCharacteristics.LENS_FACING) == targetFacing) {
                return id
            }
        }
        return null
    }
}
