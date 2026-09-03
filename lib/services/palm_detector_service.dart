import 'dart:math';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// نتيجة كشف راحة اليد (Palm Detection Result)
class PalmDetection {
  /// Bounding Box بإحداثيات normalized [0, 1] نسبة إلى أبعاد الصورة
  final Rect boundingBox;

  /// ثقة الكاشف [0.0, 1.0]
  final double confidence;

  /// مركز راحة اليد
  final double centerX;
  final double centerY;

  const PalmDetection({
    required this.boundingBox,
    required this.confidence,
    required this.centerX,
    required this.centerY,
  });

  @override
  String toString() =>
      'Palm(conf=${confidence.toStringAsFixed(2)}, '
      'cx=${centerX.toStringAsFixed(2)}, cy=${centerY.toStringAsFixed(2)}, '
      'box=[${boundingBox.left.toStringAsFixed(2)},${boundingBox.top.toStringAsFixed(2)},'
      '${boundingBox.right.toStringAsFixed(2)},${boundingBox.bottom.toStringAsFixed(2)}])';
}

/// Stage 1: كاشف راحة اليد (Palm Detector) المبني على TFLite حقيقي
///
/// يشغّل نموذج MediaPipe Palm Detection الرسمي من Google لاكتشاف الأيدي
/// البشرية في الإطار قبل تشغيل Hand Landmarker.
///
/// النموذج المستخدم: palm_detection_lite.tflite (MediaPipe BlazePalm)
/// حجم المدخل: 192×192 RGB
/// المخرجات:
///   - Tensor[0]: Regressors   shape [1, 2016, 18]  — bounding boxes + keypoints
///   - Tensor[1]: Classificators shape [1, 2016, 1] — confidence scores
class PalmDetectorService {
  static const String _modelPath = 'assets/models/palm_detection.tflite';
  static const int _inputSize = 192;
  static const double _detectionThreshold = 0.60;
  static const double _iouThreshold = 0.3;

  Interpreter? _interpreter;
  bool _isInitialized = false;
  bool _isProcessing = false;

  bool get isInitialized => _isInitialized;

  /// تهيئة النموذج وتحميله من الـ assets
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('[PalmDetector] Model loaded: $_modelPath');
        debugPrint(
          '[PalmDetector] Input shape: ${_interpreter!.getInputTensor(0).shape}',
        );
        debugPrint(
          '[PalmDetector] Output[0] shape: ${_interpreter!.getOutputTensor(0).shape}',
        );
        debugPrint(
          '[PalmDetector] Output[1] shape: ${_interpreter!.getOutputTensor(1).shape}',
        );
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[PalmDetector] Failed to load model: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// كشف الأيدي في الإطار — يعيد قائمة بأماكن الأيدي المكتشفة
  Future<List<PalmDetection>> detect(CameraImage image) async {
    if (!_isInitialized || _interpreter == null || _isProcessing) {
      return const [];
    }
    _isProcessing = true;

    try {
      // 1. تحويل الصورة إلى تنسيق مدخل النموذج [1, 192, 192, 3] Float32
      final inputTensor = _preprocessImage(image);
      if (inputTensor == null) return const [];

      // 2. تجهيز مصفوفات المخرجات
      // Output[0]: Regressors   [1, 2016, 18] — إحداثيات BBox + keypoints
      // Output[1]: Classificators [1, 2016, 1] — درجة الثقة (raw score قبل sigmoid)
      final outputRegressors = List.filled(
        1 * 2016 * 18,
        0.0,
      ).reshape([1, 2016, 18]);
      final outputScores = List.filled(1 * 2016 * 1, 0.0).reshape([1, 2016, 1]);

      final outputs = {0: outputRegressors, 1: outputScores};

      // 3. تشغيل النموذج
      _interpreter!.runForMultipleInputs([inputTensor], outputs);

      // 4. استخراج النتائج وتطبيق فلاتر الثقة والـ NMS
      return _decodeDetections(
        outputRegressors as List<List<List<double>>>,
        outputScores as List<List<List<double>>>,
        image.width,
        image.height,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PalmDetector] Inference error: $e');
      return const [];
    } finally {
      _isProcessing = false;
    }
  }

  /// تحويل CameraImage إلى tensor مدخل للنموذج [1, 192, 192, 3]
  Float32List? _preprocessImage(CameraImage image) {
    try {
      final int imgW = image.width;
      final int imgH = image.height;

      // تحويل YUV إلى RGB عبر Y-plane فقط (أسرع وكافٍ للكشف)
      final yPlane = image.planes[0].bytes;
      final uPlane = image.planes.length > 1 ? image.planes[1].bytes : null;
      final vPlane = image.planes.length > 2 ? image.planes[2].bytes : null;
      final yRowStride = image.planes[0].bytesPerRow;
      final uvRowStride = image.planes.length > 1
          ? image.planes[1].bytesPerRow
          : 0;
      final uvPixelStride = image.planes.length > 1
          ? image.planes[1].bytesPerPixel ?? 1
          : 1;

      // تخصيص مصفوفة المدخل [1, 192, 192, 3]
      final inputBytes = Float32List(1 * _inputSize * _inputSize * 3);

      final double scaleX = imgW / _inputSize;
      final double scaleY = imgH / _inputSize;

      int bufferIdx = 0;

      for (int row = 0; row < _inputSize; row++) {
        final srcY = (row * scaleY).toInt().clamp(0, imgH - 1);
        final yRowOffset = srcY * yRowStride;
        final uvRowOffset = (srcY ~/ 2) * uvRowStride;

        for (int col = 0; col < _inputSize; col++) {
          final srcX = (col * scaleX).toInt().clamp(0, imgW - 1);

          final yVal = yPlane[yRowOffset + srcX] & 0xFF;

          double r, g, b;

          if (uPlane != null && vPlane != null) {
            // YUV420 → RGB
            final uvIdx = (srcX ~/ 2) * uvPixelStride;
            final uVal = (uPlane[uvRowOffset + uvIdx] & 0xFF) - 128;
            final vVal = (vPlane[uvRowOffset + uvIdx] & 0xFF) - 128;

            r = (yVal + 1.402 * vVal).clamp(0, 255);
            g = (yVal - 0.344136 * uVal - 0.714136 * vVal).clamp(0, 255);
            b = (yVal + 1.772 * uVal).clamp(0, 255);
          } else {
            // Grayscale fallback
            r = yVal.toDouble();
            g = yVal.toDouble();
            b = yVal.toDouble();
          }

          // تطبيع إلى [-1, 1] (تنسيق MediaPipe Palm Detection)
          inputBytes[bufferIdx++] = (r / 127.5) - 1.0;
          inputBytes[bufferIdx++] = (g / 127.5) - 1.0;
          inputBytes[bufferIdx++] = (b / 127.5) - 1.0;
        }
      }

      return inputBytes;
    } catch (e) {
      if (kDebugMode) debugPrint('[PalmDetector] Preprocess error: $e');
      return null;
    }
  }

  /// فك ترميز مخرجات النموذج وتطبيق NMS
  List<PalmDetection> _decodeDetections(
    List<List<List<double>>> regressors,
    List<List<List<double>>> scores,
    int imgW,
    int imgH,
  ) {
    const int numAnchors = 2016;
    final detections = <PalmDetection>[];

    // أبعاد الـ anchor grid لنموذج BlazePalm Lite (192×192 مدخل)
    // يمكن تبسيطها: كل detection هو BBox مركزي + أبعاد
    for (int i = 0; i < numAnchors; i++) {
      // تطبيق sigmoid على الـ raw score
      final rawScore = scores[0][i][0];
      final conf = _sigmoid(rawScore);

      if (conf < _detectionThreshold) continue;

      // مختصرات إحداثيات الـ BBox (المخرج الأول من regression head)
      // التنسيق: [cx, cy, w, h, kp0x, kp0y, ...]
      final cx = regressors[0][i][0] / _inputSize;
      final cy = regressors[0][i][1] / _inputSize;
      final w = regressors[0][i][2] / _inputSize;
      final h = regressors[0][i][3] / _inputSize;

      final left = (cx - w / 2).clamp(0.0, 1.0);
      final top = (cy - h / 2).clamp(0.0, 1.0);
      final right = (cx + w / 2).clamp(0.0, 1.0);
      final bottom = (cy + h / 2).clamp(0.0, 1.0);

      // تجاهل الـ detections ذات الأبعاد المنهارة
      if ((right - left) < 0.01 || (bottom - top) < 0.01) continue;

      detections.add(
        PalmDetection(
          boundingBox: Rect.fromLTRB(left, top, right, bottom),
          confidence: conf,
          centerX: cx,
          centerY: cy,
        ),
      );
    }

    if (detections.isEmpty) return const [];

    // ترتيب تنازلياً حسب الثقة ثم تطبيق NMS
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    return _applyNMS(detections);
  }

  /// Non-Maximum Suppression — يُبقي فقط الـ detections الأفضل
  List<PalmDetection> _applyNMS(List<PalmDetection> dets) {
    final result = <PalmDetection>[];
    final suppressed = List<bool>.filled(dets.length, false);

    for (int i = 0; i < dets.length; i++) {
      if (suppressed[i]) continue;
      result.add(dets[i]);

      for (int j = i + 1; j < dets.length; j++) {
        if (suppressed[j]) continue;
        final iou = _computeIoU(dets[i].boundingBox, dets[j].boundingBox);
        if (iou > _iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return result;
  }

  double _computeIoU(Rect a, Rect b) {
    final intersectLeft = max(a.left, b.left);
    final intersectTop = max(a.top, b.top);
    final intersectRight = min(a.right, b.right);
    final intersectBottom = min(a.bottom, b.bottom);

    if (intersectRight <= intersectLeft || intersectBottom <= intersectTop) {
      return 0.0;
    }

    final intersection =
        (intersectRight - intersectLeft) * (intersectBottom - intersectTop);
    final union = a.width * a.height + b.width * b.height - intersection;
    return union > 0 ? intersection / union : 0.0;
  }

  double _sigmoid(double x) => 1.0 / (1.0 + exp(-x));

  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
