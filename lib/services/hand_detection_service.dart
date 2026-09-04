import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hand_detection/hand_detection.dart' as hd;
import 'package:ishara/models/landmarks_model.dart';

/// HandDetectionService — نقطة الدخول الوحيدة لكشف اليد
///
/// يستخدم حزمة hand_detection الرسمية (MediaPipe على TFLite) مباشرةً
/// لاكتشاف الأيدي الحقيقية واستخراج الـ 21 نقطة في الوقت الحقيقي.
/// مع دعم دوران الإطار والكاميرا الأمامية/الخلفية بدقة.
class HandDetectionService {
  static const double _detectorConf = 0.70;
  static const double _minLandmarkScore = 0.45;
  static const int _maxDetections = 2;
  static const int _maxDim = 640;

  hd.HandDetector? _detector;
  bool _isInitialized = false;
  bool _isProcessing = false;

  bool get isInitialized => _isInitialized;

  void resetState() {
    _isProcessing = false;
  }

  /// تهيئة النموذج — يُشغَّل مرة واحدة عند بدء التطبيق
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      _detector = await hd.HandDetector.create(
        mode: hd.HandMode.boxesAndLandmarks,
        detectorConf: _detectorConf,
        minLandmarkScore: _minLandmarkScore,
        maxDetections: _maxDetections,
        enableTracking: true,
        performanceConfig: hd.PerformanceConfig.xnnpack(numThreads: 2),
      );
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint(
          '[HandDetectionService] ✅ Initialized — hand_detection v4.1.0',
        );
      }
    } catch (e) {
      _isInitialized = false;
      if (kDebugMode) {
        debugPrint('[HandDetectionService] ❌ Init error: $e');
      }
    }
  }

  /// كشف اليد من CameraImage — الوظيفة الرئيسية
  /// مع ضبط التدوير والكاميرا الأمامية/الخلفية
  Future<HandLandmarks?> detectHands(
    CameraImage image, {
    int frameId = 0,
    int? sensorOrientation,
    bool isFrontCamera = false,
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
  }) async {
    if (!_isInitialized || _detector == null || _isProcessing) return null;

    _isProcessing = true;
    try {
      // حساب زاوية التدوير المناسبة للمستشعر واتجاه الجهاز والكاميرا الأمامية/الخلفية
      final hd.CameraFrameRotation? rotation = sensorOrientation == null
          ? null
          : hd.rotationForFrame(
              width: image.width,
              height: image.height,
              sensorOrientation: sensorOrientation,
              isFrontCamera: isFrontCamera,
              deviceOrientation: deviceOrientation,
            );

      final Size detSize = hd.detectionSize(
        width: image.width,
        height: image.height,
        rotation: rotation,
        maxDim: _maxDim,
      );

      // كشف الأيدي — يعمل خارج الـ UI thread تلقائياً (isolate داخلي)
      final List<hd.Hand> hands = await _detector!.detectFromCameraImage(
        image,
        rotation: rotation,
        isBgra: Platform.isMacOS,
        maxDim: _maxDim,
      );

      // RULE: hands.isEmpty → لا يد حقيقية → مسح فوري
      if (hands.isEmpty) return null;

      // اختيار أفضل يد (الأولى في القائمة — الأعلى ثقةً)
      final hd.Hand bestHand = hands.first;

      // التحقق من توفر الـ 21 نقطة
      if (!bestHand.hasLandmarks || bestHand.landmarks.length != 21) {
        return null;
      }

      // أبعاد فضاء الكشف المحسوبة بعد الدوران
      final double dW = detSize.width;
      final double dH = detSize.height;
      if (dW <= 0 || dH <= 0) return null;

      // تحويل Hand → HandLandmarks مع تطبيع الإحداثيات
      return _toHandLandmarks(
        hand: bestHand,
        detW: dW,
        detH: dH,
        frameId: frameId,
        handsCount: hands.length,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[HandDetectionService] Error: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ────────────────────────────────────────────────────────────────────────

  /// تحويل [hd.Hand] → [HandLandmarks] مع تطبيع الإحداثيات إلى [0..1]
  HandLandmarks? _toHandLandmarks({
    required hd.Hand hand,
    required double detW,
    required double detH,
    required int frameId,
    required int handsCount,
  }) {
    try {
      final rawLms = hand.landmarks;
      if (rawLms.length != 21) return null;

      final converted = <HandLandmark>[];
      double totalVis = 0.0;

      for (int i = 0; i < 21; i++) {
        final lm = rawLms[i];
        // تطبيع pixel → [0..1]
        final nx = (lm.x / detW).clamp(0.0, 1.0);
        final ny = (lm.y / detH).clamp(0.0, 1.0);
        final nz = lm.z / detW;

        converted.add(HandLandmark(index: i, x: nx, y: ny, z: nz));
        totalVis += lm.visibility;
      }

      // متوسط visibility كتقدير للثقة الكلية
      final avgConf = (totalVis / 21.0).clamp(0.5, 1.0);

      // تحديد اليد اليمنى/اليسرى
      final Handedness side;
      if (hand.handedness == hd.Handedness.left) {
        side = Handedness.left;
      } else if (hand.handedness == hd.Handedness.right) {
        side = Handedness.right;
      } else {
        side = Handedness.unknown;
      }

      if (kDebugMode) {
        final buf = StringBuffer('Hands: $handsCount\nLandmarks: 21\n');
        for (int i = 0; i < 21; i++) {
          final lm = converted[i];
          buf.writeln(
            'Point $i: x=${lm.x.toStringAsFixed(3)}, '
            'y=${lm.y.toStringAsFixed(3)}, '
            'z=${lm.z.toStringAsFixed(4)}',
          );
        }
        debugPrint(buf.toString());
      }

      return HandLandmarks(
        landmarks: converted,
        handedness: side,
        handDetectorConfidence: avgConf,
        mediaPipePresenceConfidence: avgConf,
        trackingConfidence: avgConf,
        confidence: avgConf,
        frameId: frameId,
        detectedHandsCount: handsCount,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[HandDetectionService] Convert error: $e');
      return null;
    }
  }

  Future<void> dispose() async {
    await _detector?.dispose();
    _detector = null;
    _isInitialized = false;
  }
}
