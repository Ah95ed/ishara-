package com.Ishara.iq.ishara

import com.Ishara.iq.ishara.bridge.IsharaFlutterBridge
import com.Ishara.iq.ishara.bridge.NativeCameraPreviewFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var bridge: IsharaFlutterBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val newBridge = IsharaFlutterBridge(
            activity = this,
            lifecycleOwner = this,
            binaryMessenger = flutterEngine.dartExecutor.binaryMessenger
        )
        bridge = newBridge

        flutterEngine.platformViewsController.registry.registerViewFactory(
            IsharaFlutterBridge.PREVIEW_VIEW_TYPE,
            NativeCameraPreviewFactory { previewView ->
                newBridge.onPreviewViewCreated(previewView)
            }
        )
    }

    override fun onDestroy() {
        bridge?.dispose()
        bridge = null
        super.onDestroy()
    }
}
