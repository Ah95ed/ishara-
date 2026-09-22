import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ويدجت عرض الكاميرا الأصلية (NativeCameraPreviewWidget)
/// يعرض CameraX PreviewView عبر Android PlatformView مباشرة
/// بدون أي نسخ للبكسلات أو تمرير إطارات خام إلى Dart.
class NativeCameraPreviewWidget extends StatelessWidget {
  const NativeCameraPreviewWidget({super.key});

  static const String viewType = 'com.ishara.native_vision/camera_preview';

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Center(
        child: Text(
          'Native Vision is only supported on Android',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return const AndroidView(
      viewType: viewType,
      layoutDirection: TextDirection.ltr,
      creationParamsCodec: StandardMessageCodec(),
    );
  }
}
