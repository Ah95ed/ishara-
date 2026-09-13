import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/services/pose/pose_extractor_service.dart';
import 'package:ishara/services/pose/pose_preprocessor.dart';
import 'package:ishara/services/tflite/ctc_greedy_decoder.dart';
import 'package:ishara/services/tflite/frame_buffer.dart';
import 'package:ishara/services/tflite/ishara_recognition_service.dart';
import 'package:ishara/services/tflite/ishara_vocab_service.dart';
import 'package:ishara/services/tflite/prediction_stabilizer.dart';

/// مزود الحالة الرئيسي لتمييز لغة الإشارة العربية (SignRecognitionProvider)
/// يدير نموذج TFLite، مفكك شفرة CTC، مخزن الـ 128 إطار، والمعالجة المسبقة.
class SignRecognitionProvider extends ChangeNotifier {
  final IsharaRecognitionService _modelService;
  final IsharaVocabService _vocabService;
  final PosePreprocessor _preprocessor;
  final FrameBuffer _frameBuffer;
  final PoseExtractorService _poseExtractor;
  final PredictionStabilizer _stabilizer;
  late final CtcGreedyDecoder _ctcDecoder;

  bool _isModelLoaded = false;
  bool _isRecognizing = false;
  bool _isInferenceRunning = false;
  String? _currentGloss;
  List<String> _currentGlossSequence = [];
  double? _confidence;
  String? _error;

  SignRecognitionProvider({
    IsharaRecognitionService? modelService,
    IsharaVocabService? vocabService,
    PosePreprocessor? preprocessor,
    FrameBuffer? frameBuffer,
    PoseExtractorService? poseExtractor,
    PredictionStabilizer? stabilizer,
  })  : _modelService = modelService ?? IsharaRecognitionService(),
        _vocabService = vocabService ?? IsharaVocabService(),
        _preprocessor = preprocessor ?? PosePreprocessor(),
        _frameBuffer = frameBuffer ?? FrameBuffer(inferenceStride: 8, minActiveRatio: 0.30),
        _poseExtractor = poseExtractor ?? PoseExtractorService(),
        _stabilizer = stabilizer ?? PredictionStabilizer() {
    _ctcDecoder = CtcGreedyDecoder(vocabService: _vocabService);
  }

  // Getters المطلوبة للمستخدم والواجهة
  bool get isModelLoaded => _isModelLoaded;
  bool get isRecognizing => _isRecognizing;
  String? get currentGloss => _currentGloss;
  List<String> get currentGlossSequence => List.unmodifiable(_currentGlossSequence);
  double? get confidence => _confidence;
  String? get error => _error;
  double get bufferFillRatio => _frameBuffer.count / FrameBuffer.requiredFrames;

  /// تهيئة النموذج والمفردات ومحرك الكشف
  Future<bool> initialize() async {
    _error = null;
    notifyListeners();

    try {
      // 1. تحميل المفردات
      final vocabOk = await _vocabService.loadVocab();
      if (!vocabOk) {
        _error = 'فشل تحميل قاموس المفردات (ishara_vocab.json)';
        notifyListeners();
        return false;
      }

      // 2. تحميل نموذج TFLite والتحقق من أبعاد الدخل [1, 128, 86, 2] والخرج [1, 29, 684]
      final modelOk = await _modelService.loadModel();
      if (!modelOk) {
        _error = 'فشل تحميل نموذج لغة الإشارة (ishara_model.tflite)';
        notifyListeners();
        return false;
      }

      // 3. تهيئة مستخرج المعالم من الكاميرا
      await _poseExtractor.initialize();

      _isModelLoaded = true;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _isModelLoaded = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// بدء عملية التعرف المستمر
  void startRecognition() {
    if (!_isModelLoaded) {
      _error = 'النموذج غير جاهز للبدء';
      notifyListeners();
      return;
    }
    _isRecognizing = true;
    _frameBuffer.clear();
    _preprocessor.reset();
    _stabilizer.clear();
    _currentGloss = null;
    _currentGlossSequence.clear();
    _confidence = null;
    _error = null;
    notifyListeners();
  }

  /// إيقاف التعرف مؤقتاً
  void stopRecognition() {
    _isRecognizing = false;
    _frameBuffer.clear();
    _preprocessor.reset();
    _stabilizer.clear();
    notifyListeners();
  }

  /// معالجة إطار الكاميرا الوارد
  Future<void> processFrame(
    CameraImage image, {
    int? sensorOrientation,
    bool isFrontCamera = false,
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
  }) async {
    if (!_isModelLoaded || !_isRecognizing || _isInferenceRunning) return;

    try {
      // 1. استخراج معالم الأيدي والوضعيات من الكاميرا
      final extracted = await _poseExtractor.extractFromCameraImage(
        image,
        sensorOrientation: sensorOrientation,
        isFrontCamera: isFrontCamera,
        deviceOrientation: deviceOrientation,
      );

      // 2. تطبيق المعالجة المسبقة والتطبيع الصارم المطابق لـ datasetv2.py
      final frame86x2 = _preprocessor.processFrame(
        rawRightHand: extracted.rightHand,
        rawLeftHand: extracted.leftHand,
        rawLips: extracted.lips,
        rawBody: extracted.body,
      );

      // 3. حفظ الإطار في المخزن الزمني
      _frameBuffer.addFrame(
        frame86x2,
        hasActivePerson: extracted.hasActiveDetection,
      );

      // 4. فحص ما إذا كان هناك نشاط حقيقي أو يجب مسح التنبؤ الشبح
      if (!extracted.hasActiveDetection && !_frameBuffer.hasValidSignActivity) {
        if (_currentGloss != null) {
          _stabilizer.onSignEnded();
          _currentGloss = null;
          notifyListeners();
        }
        return;
      }

      // 5. فحص ما إذا حان موعد تشغيل الاستنتاج عبر النافذة الانزلاقية
      if (_frameBuffer.shouldTriggerInference() && _frameBuffer.hasValidSignActivity) {
        final frames = _frameBuffer.getFrames();
        if (frames != null) {
          _frameBuffer.markInferenceExecuted();
          _executeInference(frames);
        }
      }
    } catch (e) {
      debugPrint('[SignRecognitionProvider] Frame process error: $e');
    }
  }

  /// تنفيذ الاستنتاج وفك التشفير في خلفية سريعة دون تجميد واجهة المستخدم
  void _executeInference(List<List<List<double>>> frames128x86x2) {
    if (_isInferenceRunning) return;
    _isInferenceRunning = true;

    try {
      // تشغيل الموديل للحصول على مصفوفة الـ Logits [29, 684]
      final logits29x684 = _modelService.runInference(frames128x86x2);

      if (logits29x684 != null) {
        // فك التشفير عبر CTC Greedy Decoder
        final decoded = _ctcDecoder.decodeLogits(logits29x684);

        if (decoded.isNotEmpty) {
          final candidate = decoded.glosses.join(' ');
          final conf = decoded.averageConfidence;

          // تمرير النتيجة إلى مثبت التنبؤات لمنع التكرار والنتائج الوهمية
          final stableGloss = _stabilizer.processPrediction(
            candidateGloss: candidate,
            confidence: conf,
            isSignActive: true,
          );

          if (stableGloss != null && stableGloss.isNotEmpty) {
            _currentGloss = stableGloss;
            _currentGlossSequence = List.from(_stabilizer.glossSequence);
            _confidence = conf;
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('[SignRecognitionProvider] Inference error: $e');
    } finally {
      _isInferenceRunning = false;
    }
  }

  /// مسح التنبؤات والذاكرة اللحظية
  void clearPrediction() {
    _currentGloss = null;
    _currentGlossSequence.clear();
    _confidence = null;
    _stabilizer.clear();
    _frameBuffer.clear();
    _preprocessor.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    stopRecognition();
    _modelService.dispose();
    _poseExtractor.dispose();
    _vocabService.clear();
    _frameBuffer.clear();
    _preprocessor.reset();
    _stabilizer.clear();
    super.dispose();
  }
}
