package com.Ishara.iq.ishara.bridge

import android.content.Context
import android.view.View
import androidx.camera.view.PreviewView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * PlatformView لعرض الكاميرا الأصلية (NativeCameraPreviewView)
 * يستضيف PreviewView الخاص بـ CameraX مباشرة على عتاد الجهاز
 * دون أي نسخ للبكسلات أو تمرير إطارات خام إلى Dart.
 */
class NativeCameraPreviewView(
    private val context: Context,
    viewId: Int,
    args: Any?,
    private val onPreviewViewCreated: (PreviewView) -> Unit
) : PlatformView {

    private val previewView: PreviewView = PreviewView(context).apply {
        scaleType = PreviewView.ScaleType.FILL_CENTER
        implementationMode = PreviewView.ImplementationMode.PERFORMANCE
    }

    init {
        onPreviewViewCreated(previewView)
    }

    override fun getView(): View = previewView

    override fun dispose() {
        // يتم تحرير الموارد من خلال CameraEngine
    }
}

class NativeCameraPreviewFactory(
    private val onPreviewViewCreated: (PreviewView) -> Unit
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NativeCameraPreviewView(context, viewId, args, onPreviewViewCreated)
    }
}
