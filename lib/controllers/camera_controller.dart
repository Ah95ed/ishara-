import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/models/landmarks_model.dart';
import 'package:ishara/services/camera_service.dart';
import 'package:ishara/services/diagnostics/ishara_diagnostic_service.dart';
import 'package:ishara/services/hand_detection_service.dart';
import 'package:permission_handler/permission_handler.dart';

enum CameraStatus { initial, loading, ready, streaming, error }

class CameraProvider extends ChangeNotifier {
  final CameraService _cameraService;
  final HandDetectionService _handDetectionService;

  CameraStatus _status = CameraStatus.initial;
  String? _errorMessage;
  CameraImage? _latestImage;

  bool _isSwitchingCamera = false;
  void Function(CameraImage image)? _streamCallback;

  // قفل الفريمات ومنع التراكم (Frame Throttling & Busy Drop)
  bool _isProcessingFrame = false;
  int _currentFrameSequence = 0;
  DateTime? _lastProcessedFrameTime;

  // نتيجة آخر كشف
  HandLandmarks? _latestLandmarks;
  bool _isRealHand = false;

  // إحصائيات الأداء
  int _droppedFramesCount = 0;
  int _processedFramesCount = 0;
  double _lastProcessingTimeMs = 0.0;
  double _currentFps = 0.0;
  DateTime? _lastFpsCalculationTime;
  int _fpsFrameCounter = 0;

  CameraProvider(this._cameraService, this._handDetectionService);

  // ────────────────────────────────── Getters ──────────────────────────────────
  CameraStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isReady => _status == CameraStatus.ready || _status == CameraStatus.streaming;
  bool get hasError => _status == CameraStatus.error;
  bool get isStreaming => _status == CameraStatus.streaming;
  bool get isSwitchingCamera => _isSwitchingCamera;
  CameraImage? get latestImage => _latestImage;
  CameraController? get cameraController => _cameraService.controller;

  /// المعالم الـ 21 — null عند عدم وجود يد
  HandLandmarks? get latestLandmarks => _isRealHand ? _latestLandmarks : null;

  /// هل هناك يد بشرية حقيقية مكتشفة؟
  bool get isRealHand => _isRealHand;
  bool get isConfirmedHumanHand => _isRealHand;
  bool get hasStableHand => _isRealHand;

  // مؤشرات للتوافق مع debug panel الحالي
  bool get rawHandDetected => _isRealHand;
  double get handDetectorConfidence => _latestLandmarks?.handDetectorConfidence ?? 0.0;
  double get mediaPipePresenceConfidence => _latestLandmarks?.mediaPipePresenceConfidence ?? 0.0;
  double get trackingConfidence => _latestLandmarks?.trackingConfidence ?? 0.0;
  int get frameId => _currentFrameSequence;
  int get resultFrameId => _latestLandmarks?.frameId ?? 0;
  bool get isStaleResult => false;
  bool get geometryValid => _isRealHand;
  String get rejectionReason => _isRealHand ? 'NONE' : 'NO_HAND';
  int get consecutiveValidFrames => _isRealHand ? 3 : 0;
  HandPresenceState get presenceState => _isRealHand
      ? HandPresenceState.confirmedHumanHand
      : HandPresenceState.noHand;

  // إحصائيات الأداء
  int get droppedFramesCount => _droppedFramesCount;
  int get processedFramesCount => _processedFramesCount;
  double get lastProcessingTimeMs => _lastProcessingTimeMs;
  double get currentFps => _currentFps;
  bool get isProcessingFrame => _isProcessingFrame;

  // مواصفات إطارات الكاميرا (المرحلة 1)
  int get imageWidth => _latestImage?.width ?? 0;
  int get imageHeight => _latestImage?.height ?? 0;
  String get imageFormat => _latestImage?.format.group.name ?? 'unknown';
  bool get isFrontCamera => _cameraService.isFrontCamera;
  int get sensorRotation => _cameraService.sensorOrientation ?? 0;
  int get previewRotation => _cameraService.sensorOrientation ?? 0;
  int get detectorRotation => _cameraService.sensorOrientation ?? 0;

  // ────────────────────────────────── Methods ──────────────────────────────────

  Future<void> toggleStream(void Function(CameraImage image) onImage) async {
    if (isStreaming) {
      await stopStream();
    } else {
      await startStream(onImage);
    }
  }

  /// تبديل الكاميرا (الأمامية ↔ الخلفية) وفق الخطوات الـ 8 المحددة بدقة
  Future<void> switchCamera() async {
    if (_isSwitchingCamera) return;
    _isSwitchingCamera = true;
    notifyListeners();

    try {
      final wasStreaming = isStreaming;

      // 1. أوقف image stream الحالي
      if (wasStreaming) {
        await stopStream();
      }

      // 2. dispose للـ CameraController القديم بشكل آمن (يتم داخل CameraService)
      // 3. اختر الكاميرا الأخرى
      final nextLens = _cameraService.currentLens == CameraLensDirection.back
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      // 4 + 5. أنشئ CameraController جديد مع initialize
      await _cameraService.initialize(lensDirection: nextLens);

      // 6. أعد تشغيل image stream
      if (wasStreaming && _streamCallback != null) {
        await startStream(_streamCallback!);
      } else {
        _setStatus(CameraStatus.ready);
      }

      // 7. أعد ربط Hand Detection وتفريغ الحالة السابقة
      _clearHand();
      _handDetectionService.resetState();

      // 8. حدث Provider/UI
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[CameraProvider] switchCamera error: $e');
      _setStatus(CameraStatus.error, 'تعذر تبديل الكاميرا: $e');
    } finally {
      _isSwitchingCamera = false;
      notifyListeners();
    }
  }

  Future<bool> requestPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    final result = await Permission.camera.request();
    if (result.isGranted) return true;
    _setStatus(CameraStatus.error, AppConstants.permissionDeniedMessage);
    return false;
  }

  Future<void> initializeCamera() async {
    if (!await requestPermission()) return;
    _setStatus(CameraStatus.loading);
    try {
      await _cameraService.initialize();
      _setStatus(CameraStatus.ready);
    } catch (e) {
      _setStatus(CameraStatus.error, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> startStream(void Function(CameraImage image) onImage) async {
    if (!_cameraService.isInitialized) return;
    _streamCallback = onImage;
    _clearHand();
    _currentFrameSequence = 0;
    _fpsFrameCounter = 0;
    _lastFpsCalculationTime = DateTime.now();
    _setStatus(CameraStatus.streaming);
    await _cameraService.startStream(onImage);
  }

  Future<void> stopStream() async {
    await _cameraService.stopStream();
    _clearHand();
    _setStatus(CameraStatus.ready);
  }

  /// معالجة إطار الكاميرا — نقطة الدخول الرئيسية مع خفض الفريمات (10-15 FPS)
  Future<void> processFrame(CameraImage image) async {
    _currentFrameSequence++;

    // 1. خفض معدل الفريمات (Frame Throttling: 10-15 FPS)
    final now = DateTime.now();
    if (_lastProcessedFrameTime != null) {
      final elapsedMs = now.difference(_lastProcessedFrameTime!).inMilliseconds;
      if (elapsedMs < AppConstants.frameThrottleMs) {
        _droppedFramesCount++;
        return;
      }
    }

    // 2. إسقاط الفريم فوراً إذا كان الاستنتاج السابق قيد التشغيل (لا طوابير)
    if (_isProcessingFrame) {
      _droppedFramesCount++;
      return;
    }

    _isProcessingFrame = true;
    _latestImage = image;
    final sw = Stopwatch()..start();

    try {
      _calcFps();

      final frameAge = _lastProcessedFrameTime != null
          ? now.difference(_lastProcessedFrameTime!).inMilliseconds
          : 0;

      IsharaDiagnosticService().recordCamera(
        isInitialized: _cameraService.isInitialized,
        isStreaming: isStreaming,
        fps: _currentFps,
        frameAgeMs: frameAge,
        width: image.width,
        height: image.height,
        format: image.format.group.name,
        rotation: _cameraService.sensorOrientation ?? 0,
        previewRotation: previewRotation,
        detectorInputRotation: detectorRotation,
        isFrontCamera: isFrontCamera,
        framesReceived: _currentFrameSequence,
      );

      sw.stop();
      _lastProcessingTimeMs = sw.elapsedMicroseconds / 1000.0;
      _processedFramesCount++;
      _lastProcessedFrameTime = DateTime.now();

      // تحديث واجهة التشخيص بشكل دوري
      if (_processedFramesCount % 3 == 0) {
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CameraProvider] Error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _clearHand() {
    _latestLandmarks = null;
    _isRealHand = false;
  }

  void _calcFps() {
    _fpsFrameCounter++;
    final now = DateTime.now();
    if (_lastFpsCalculationTime == null) {
      _lastFpsCalculationTime = now;
      return;
    }
    final elapsed = now.difference(_lastFpsCalculationTime!).inMilliseconds;
    if (elapsed >= 1000) {
      _currentFps = (_fpsFrameCounter * 1000.0) / elapsed;
      _fpsFrameCounter = 0;
      _lastFpsCalculationTime = now;
    }
  }

  void _setStatus(CameraStatus status, [String? error]) {
    _status = status;
    _errorMessage = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _cameraService.dispose();
    _handDetectionService.dispose();
    super.dispose();
  }
}
