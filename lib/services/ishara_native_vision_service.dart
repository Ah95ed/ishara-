import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// حالات الإشارة الأصلية القادمة من Native Kotlin
enum NativeSignState {
  idle,
  starting,
  signing,
  ending,
  processing,
  result,
  failed;

  static NativeSignState fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'STARTING':
        return NativeSignState.starting;
      case 'SIGNING':
        return NativeSignState.signing;
      case 'ENDING':
        return NativeSignState.ending;
      case 'PROCESSING':
        return NativeSignState.processing;
      case 'RESULT':
        return NativeSignState.result;
      case 'FAILED':
        return NativeSignState.failed;
      case 'IDLE':
      default:
        return NativeSignState.idle;
    }
  }

  String get localizedTitle {
    switch (this) {
      case NativeSignState.idle:
        return 'جاهز';
      case NativeSignState.starting:
        return 'بدأت الحركة...';
      case NativeSignState.signing:
        return 'جاري أداء الإشارة...';
      case NativeSignState.ending:
        return 'اكتملت الإشارة...';
      case NativeSignState.processing:
        return 'جاري التحليل...';
      case NativeSignState.result:
        return 'النتيجة';
      case NativeSignState.failed:
        return 'لم تكتمل الإشارة';
    }
  }
}

/// خدمة الرؤية الأصلية (IsharaNativeVisionService)
/// تدير الاتصال عالي الأداء مع Native Android Kotlin عبر MethodChannel و EventChannel.
/// لا تستقبل أي إطارات صور خام عبر Dart، وتستلم فقط الحالات والأحداث الخفيفة.
class IsharaNativeVisionService extends ChangeNotifier {
  static const MethodChannel _commandChannel =
      MethodChannel('com.ishara.native_vision/commands');
  static const EventChannel _eventChannel =
      EventChannel('com.ishara.native_vision/events');

  StreamSubscription? _eventSubscription;

  bool _isInitialized = false;
  bool _isCameraRunning = false;
  bool _isFrontCamera = true;
  NativeSignState _state = NativeSignState.idle;

  List<String> _lastGlosses = [];
  List<int> _lastDecodedIds = [];
  int _lastInferenceMs = 0;
  int _lastDurationMs = 0;
  int _lastOriginalFrames = 0;
  String _displayResult = '';
  String? _errorMessage;
  String _latestDiagnosticReport = '';

  Map<String, dynamic> _capabilities = {};
  Map<String, dynamic> _performanceMetrics = {};

  // ── Getters ──
  bool get isInitialized => _isInitialized;
  bool get isCameraRunning => _isCameraRunning;
  bool get isFrontCamera => _isFrontCamera;
  NativeSignState get state => _state;
  List<String> get lastGlosses => _lastGlosses;
  List<int> get lastDecodedIds => _lastDecodedIds;
  int get lastInferenceMs => _lastInferenceMs;
  int get lastDurationMs => _lastDurationMs;
  int get lastOriginalFrames => _lastOriginalFrames;
  String get displayResult => _displayResult;
  String? get errorMessage => _errorMessage;
  String get latestDiagnosticReport => _latestDiagnosticReport;
  Map<String, dynamic> get capabilities => _capabilities;
  Map<String, dynamic> get performanceMetrics => _performanceMetrics;

  bool get isIdle => _state == NativeSignState.idle;
  bool get isSigning =>
      _state == NativeSignState.starting || _state == NativeSignState.signing || _state == NativeSignState.ending;
  bool get isProcessing => _state == NativeSignState.processing;
  bool get isResult => _state == NativeSignState.result;

  /// تهيئة المحرك الأصلي وتحميل الموديل والقاموس
  Future<bool> initialize() async {
    try {
      _startListeningEvents();
      final bool ready = await _commandChannel.invokeMethod('initializeNativeVision') ?? false;
      _isInitialized = ready;
      notifyListeners();
      return ready;
    } catch (e) {
      if (kDebugMode) debugPrint('[IsharaNativeVisionService] initialize failed: $e');
      _isInitialized = false;
      notifyListeners();
      return false;
    }
  }

  /// بدء تشغيل الكاميرا الأصلية
  Future<bool> startVision({bool useFrontCamera = true}) async {
    try {
      _isFrontCamera = useFrontCamera;
      final bool started = await _commandChannel.invokeMethod(
            'startVision',
            {'useFrontCamera': useFrontCamera},
          ) ??
          false;
      _isCameraRunning = started;
      notifyListeners();
      return started;
    } catch (e) {
      if (kDebugMode) debugPrint('[IsharaNativeVisionService] startVision failed: $e');
      return false;
    }
  }

  /// إيقاف الكاميرا
  Future<void> stopVision() async {
    try {
      await _commandChannel.invokeMethod('stopVision');
      _isCameraRunning = false;
      _state = NativeSignState.idle;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[IsharaNativeVisionService] stopVision failed: $e');
    }
  }

  /// تبديل العدسة (Front <-> Back)
  Future<void> switchCamera() async {
    try {
      _isFrontCamera = !_isFrontCamera;
      await _commandChannel.invokeMethod('switchCamera');
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[IsharaNativeVisionService] switchCamera failed: $e');
    }
  }

  /// استرجاع مقاييس الأداء الحقيقية (FPS، التأخير، الإطارات المسقطة)
  Future<Map<String, dynamic>> fetchPerformanceMetrics() async {
    try {
      final res = await _commandChannel.invokeMethod<Map>('getPerformanceMetrics');
      if (res != null) {
        _performanceMetrics = Map<String, dynamic>.from(res);
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[IsharaNativeVisionService] fetchPerformanceMetrics failed: $e');
    }
    return _performanceMetrics;
  }

  /// استرجاع تقرير التشخيص النصي الكامل (Section 35)
  Future<String> fetchDiagnosticReport() async {
    try {
      final String? report = await _commandChannel.invokeMethod('getDiagnosticReport');
      if (report != null && report.isNotEmpty) {
        _latestDiagnosticReport = report;
        return report;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[IsharaNativeVisionService] fetchDiagnosticReport failed: $e');
    }
    return _latestDiagnosticReport;
  }

  /// نسخ تقرير التشخيص الكامل إلى الحافظة
  Future<bool> copyDiagnosticReport() async {
    final report = await fetchDiagnosticReport();
    await Clipboard.setData(ClipboardData(text: report));
    return true;
  }

  /// تصفير الجلسة وبدء الاستعداد لإشارة جديدة
  Future<void> resetSession() async {
    try {
      await _commandChannel.invokeMethod('resetSession');
      _state = NativeSignState.idle;
      _displayResult = '';
      _lastGlosses = [];
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[IsharaNativeVisionService] resetSession failed: $e');
    }
  }

  /// الاستماع للأحداث الخفيفة القادمة من Native Kotlin عبر EventChannel
  void _startListeningEvents() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          _handleNativeEvent(Map<String, dynamic>.from(event));
        }
      },
      onError: (err) {
        if (kDebugMode) debugPrint('[IsharaNativeVisionService] Event error: $err');
      },
    );
  }

  void _handleNativeEvent(Map<String, dynamic> data) {
    final String? eventType = data['event'];

    switch (eventType) {
      case 'INITIALIZED':
        _isInitialized = data['modelReady'] == true;
        if (data['capabilities'] is Map) {
          _capabilities = Map<String, dynamic>.from(data['capabilities']);
        }
        break;

      case 'CAMERA_STARTED':
        _isCameraRunning = true;
        break;

      case 'CAMERA_STOPPED':
        _isCameraRunning = false;
        break;

      case 'STATE_CHANGED':
        final String? stateStr = data['state'];
        _state = NativeSignState.fromString(stateStr);
        if (_state == NativeSignState.signing) {
          _displayResult = '';
        }
        break;

      case 'RESULT':
        _state = NativeSignState.result;
        _displayResult = data['displayResult'] ?? '';
        if (data['glosses'] is List) {
          _lastGlosses = List<String>.from(data['glosses']);
        }
        if (data['decodedIds'] is List) {
          _lastDecodedIds = List<int>.from(data['decodedIds']);
        }
        _lastInferenceMs = data['inferenceMs'] ?? 0;
        _lastDurationMs = data['durationMs'] ?? 0;
        _lastOriginalFrames = data['originalFrames'] ?? 0;
        break;

      case 'FAILED':
        _state = NativeSignState.failed;
        _displayResult = 'لم تكتمل الإشارة، أعد المحاولة';
        _errorMessage = data['errorMessage'];
        break;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    stopVision();
    super.dispose();
  }
}
