import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/models/body_parts_detection_state.dart';
import 'package:ishara/models/real_inference_result.dart';
import 'package:ishara/services/real_inference_test_service.dart';
import 'package:ishara/services/vision_detection_service.dart';

/// VisionDetectionProvider
/// مزود الحالة المخصص لإدارة وعرض حالة التعرف وعدد النقاط الحقيقية للأجزاء الـ 6 ونقاط الموديل الـ 86 في الـ UI.
class VisionDetectionProvider extends ChangeNotifier {
  final VisionDetectionService _service;
  VisionLandmarksState _state = VisionLandmarksState.empty;

  VisionDetectionProvider(this._service);

  VisionLandmarksState get state => _state;
  bool get isInitialized => _service.isInitialized;
  RealInferenceTestService get realInferenceService => _service.realInferenceTestService;

  Future<void> initialize() async {
    await _service.initialize();
    notifyListeners();
  }

  Future<void> processFrame(
    CameraImage image, {
    int? sensorOrientation,
    bool isFrontCamera = true,
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
  }) async {
    final result = await _service.processFrame(
      image,
      sensorOrientation: sensorOrientation,
      isFrontCamera: isFrontCamera,
      deviceOrientation: deviceOrientation,
    );

    if (result != null) {
      _state = result;
      notifyListeners();
    }
  }

  /// تشغيل استنتاج يدوي/تشخيصي للموديل
  Future<void> runModelInference() async {
    await _service.runModelInference();
    notifyListeners();
  }

  /// التقاط عينة واستنتاج تسلسل حقيقي (TEST A أو TEST B)
  Future<SingleRealInferenceResult> captureRealInference({required String testLabel}) async {
    final result = await _service.realInferenceTestService.captureAndInfer(testLabel: testLabel);
    notifyListeners();
    return result;
  }

  /// بدء احتساب نافذة 128 إطاراً جديدة كلياً
  void startNewTestWindow() {
    _service.realInferenceTestService.startNewTestWindow();
    notifyListeners();
  }

  /// تصفير جلسة فحص الاستنتاج الحقيقي
  void resetRealInferenceSession() {
    _service.realInferenceTestService.resetSession();
    notifyListeners();
  }

  /// نسخ تقرير الاستنتاج الحقيقي إلى الحافظة
  Future<String> copyRealInferenceReport() async {
    final report = await _service.realInferenceTestService.copyReportToClipboard();
    notifyListeners();
    return report;
  }

  /// نسخ تقرير جودة التسلسل إلى الحافظة
  Future<String> copySequenceQualityReport() async {
    final text = await _service.copySequenceQualityReport();
    notifyListeners();
    return text;
  }

  void reset() {
    _service.reset();
    _state = VisionLandmarksState.empty;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
