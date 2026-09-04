import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isDisposed = false;
  CameraLensDirection _currentLens = CameraLensDirection.back;

  CameraController? get controller => _controller;
  List<CameraDescription>? get cameras => _cameras;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  CameraLensDirection get currentLens => _currentLens;
  CameraDescription? get description => _controller?.description;
  int? get sensorOrientation => _controller?.description.sensorOrientation;
  bool get isFrontCamera => _currentLens == CameraLensDirection.front;

  Future<void> initialize({CameraLensDirection? lensDirection}) async {
    if (_isDisposed) return;

    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('لا توجد كاميرات متوفرة');
      }

      _currentLens = lensDirection ?? _currentLens;

      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == _currentLens,
        orElse: () => _cameras!.first,
      );
      _currentLens = camera.lensDirection;

      await _disposeController();

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await _controller!.initialize();
    } on CameraException catch (e) {
      throw Exception(e.description ?? 'خطأ في الكاميرا');
    } catch (e) {
      throw Exception('خطأ في تهيئة الكاميرا: $e');
    }
  }

  Future<void> startStream(void Function(CameraImage image) onImage) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isStreamingImages) return;
    await _controller!.startImageStream(onImage);
  }

  Future<void> stopStream() async {
    if (_controller != null && _controller!.value.isInitialized && _controller!.value.isStreamingImages) {
      try {
        await _controller!.stopImageStream();
      } catch (_) {}
    }
  }

  Future<void> disposeController() async {
    await _disposeController();
  }

  Future<void> dispose() async {
    _isDisposed = true;
    await stopStream();
    await _disposeController();
    _controller = null;
    _cameras = null;
  }

  Future<void> _disposeController() async {
    if (_controller != null) {
      if (_controller!.value.isStreamingImages) {
        try {
          await _controller!.stopImageStream();
        } catch (_) {}
      }
      try {
        await _controller!.dispose();
      } catch (_) {}
      _controller = null;
    }
  }

  CameraLensDirection get defaultLens {
    if (_cameras == null || _cameras!.isEmpty) return CameraLensDirection.back;
    return _cameras!.first.lensDirection;
  }
}
