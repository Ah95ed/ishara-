import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/models/gloss_result.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';

enum GlossModelState {
  uninitialized,
  preparing,
  loading,
  ready,
  generating,
  error,
}

/// خدمة تشغيل نموذج Gloss2Text (Gemma3-270M GGUF) محلياً بدون خادم
/// مسؤولة عن إدارة ملف النموذج، وتهيئته مرة واحدة، وتسريع GPU/Vulkan،
/// ومنع تداخل الاستنتاج، وتخزين النتائج المؤقت (In-Memory Cache).
class GlossModelService extends ChangeNotifier {
  static const String _modelAssetPath = 'assets/models/Gloss2Text-V1-Gemma3-270M-Q5_K_M.gguf';
  static const String _modelFileName = 'Gloss2Text-V1-Gemma3-270M-Q5_K_M.gguf';
  static const int _expectedModelSizeBytes = 268230528; // ~268 MB

  GlossModelState _state = GlossModelState.uninitialized;
  String? _errorMessage;
  String? _localModelPath;
  LlamaController? _llamaController;
  StreamSubscription<String>? _generationSubscription;

  // In-Memory Cache للنتائج لتفادي إعادة التوليد
  final Map<String, GlossResult> _cache = {};

  // قياسات الأداء للمطور (Developer Telemetry)
  int _modelLoadTimeMs = 0;
  int _lastFirstTokenMs = 0;
  int _lastTotalDurationMs = 0;
  double _lastTokensPerSec = 0.0;
  int _recommendedGpuLayers = 0;
  bool _vulkanSupported = false;

  // إدارة التزامن وتفادي التداخل
  String? _pendingGloss;
  Completer<GlossResult?>? _currentCompleter;

  GlossModelState get state => _state;
  bool get isReady => _state == GlossModelState.ready;
  bool get isGenerating => _state == GlossModelState.generating;
  bool get hasError => _state == GlossModelState.error;
  String? get errorMessage => _errorMessage;
  int get modelLoadTimeMs => _modelLoadTimeMs;
  int get lastFirstTokenMs => _lastFirstTokenMs;
  int get lastTotalDurationMs => _lastTotalDurationMs;
  double get lastTokensPerSec => _lastTokensPerSec;
  int get recommendedGpuLayers => _recommendedGpuLayers;
  bool get vulkanSupported => _vulkanSupported;

  // ────────────────────────────────── 1. إدارة ملف GGUF ──────────────────────────────────

  /// التحقق من وجود ملف النموذج واستخراجه من الـ assets مرة واحدة فقط
  Future<String?> prepareModel() async {
    if (_localModelPath != null && await File(_localModelPath!).exists()) {
      return _localModelPath;
    }

    _setState(GlossModelState.preparing);

    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final targetFile = File('${appSupportDir.path}/$_modelFileName');

      // 1. فحص هل النموذج مستخرج مسبقاً بنفس الحجم الفعلي
      if (await targetFile.exists()) {
        final currentLength = await targetFile.length();
        if (currentLength == _expectedModelSizeBytes || currentLength > 260 * 1024 * 1024) {
          if (kDebugMode) {
            debugPrint('[GlossModelService] Model file already exists ($currentLength bytes). Skipping copy.');
          }
          _localModelPath = targetFile.path;
          return _localModelPath;
        } else {
          // ملف غير مكتمل أو تالف، نحذفه ونعيد نسخه
          await targetFile.delete();
        }
      }

      // 2. نسخ الملف من assets مرة واحدة فقط دون إبقاء 280MB في الذاكرة
      if (kDebugMode) {
        debugPrint('[GlossModelService] Extracting model from assets to ${targetFile.path}...');
      }

      final ByteData data = await rootBundle.load(_modelAssetPath);
      final sink = targetFile.openWrite();
      
      // كتابة البيانات بشكل كتل لتقليل الضغط
      const chunkSize = 1024 * 1024; // 1 MB
      final totalBytes = data.lengthInBytes;
      for (int offset = 0; offset < totalBytes; offset += chunkSize) {
        final end = (offset + chunkSize < totalBytes) ? offset + chunkSize : totalBytes;
        final chunk = data.buffer.asUint8List(offset, end - offset);
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      _localModelPath = targetFile.path;
      if (kDebugMode) {
        debugPrint('[GlossModelService] Model extraction complete: $_localModelPath');
      }
      return _localModelPath;
    } catch (e) {
      _setError('فشل استخراج ملف النموذج: $e');
      return null;
    }
  }

  // ────────────────────────────────── 2. تحميل النموذج والـ GPU ──────────────────────────────────

  /// تحميل النموذج لمرة واحدة فقط طوال فترة تشغيل التطبيق
  Future<bool> loadModel() async {
    if (isReady && _llamaController != null) return true;

    // التأكد من استخراج الملف أولاً
    final modelPath = await prepareModel();
    if (modelPath == null) return false;

    if (!Platform.isAndroid) {
      if (kDebugMode) {
        debugPrint('[GlossModelService] Native inference only supported on Android. Simulation mode enabled.');
      }
      _setState(GlossModelState.ready);
      return true;
    }

    _setState(GlossModelState.loading);
    final stopwatch = Stopwatch()..start();

    try {
      _llamaController = LlamaController();

      // 1. استدعاء detectGpu لمعرفة دعم الجهاز للـ Vulkan وعدد الطبقات الموصى بها
      try {
        final gpuInfo = await _llamaController!.detectGpu();
        _vulkanSupported = gpuInfo.vulkanSupported;
        _recommendedGpuLayers = gpuInfo.recommendedGpuLayers;

        if (kDebugMode) {
          debugPrint('[GlossModelService] GPU Detection:');
          debugPrint('  - GPU: ${gpuInfo.gpuName}');
          debugPrint('  - Vulkan Supported: ${gpuInfo.vulkanSupported}');
          debugPrint('  - Free RAM: ${gpuInfo.freeRamBytes ~/ 1024 ~/ 1024} MB');
          debugPrint('  - Recommended GPU Layers: ${gpuInfo.recommendedGpuLayers}');
        }
      } catch (gpuError) {
        if (kDebugMode) {
          debugPrint('[GlossModelService] GPU detection failed, falling back to CPU (0 layers): $gpuError');
        }
        _vulkanSupported = false;
        _recommendedGpuLayers = 0;
      }

      // 2. تحميل النموذج بحجم context صغير (512) لتقليل الذاكرة وتسريع الاستنتاج
      await _llamaController!.loadModel(
        modelPath: modelPath,
        gpuLayers: _recommendedGpuLayers,
        contextSize: 512,
        threads: 4,
      );

      stopwatch.stop();
      _modelLoadTimeMs = stopwatch.elapsedMilliseconds;

      if (kDebugMode) {
        debugPrint('[GlossModelService] Model loaded successfully in ${_modelLoadTimeMs}ms');
      }

      _setState(GlossModelState.ready);
      return true;
    } catch (e) {
      stopwatch.stop();
      _setError('فشل تحميل نموذج Gemma3: $e');
      return false;
    }
  }

  // ────────────────────────────────── 3. الترجمة والاستنتاج ──────────────────────────────────

  /// ترجمة تسلسل الـ Gloss إلى جملة عربية فصحى مكتملة
  Future<GlossResult?> translateGloss(String gloss) async {
    final cleanGloss = gloss.trim();
    if (cleanGloss.isEmpty) return null;

    // تطبيع المفتاح للـ Cache (مثل "أنا|ذهاب|سوق")
    final cacheKey = cleanGloss.split(RegExp(r'\s+')).join('|');

    // 1. التحقق من الـ In-Memory Cache الفوري
    if (_cache.containsKey(cacheKey)) {
      final cachedResult = _cache[cacheKey]!;
      if (kDebugMode) {
        debugPrint('[GlossModelService] Cache HIT for: "$cleanGloss" -> "${cachedResult.arabicText}"');
      }
      return GlossResult(
        gloss: cleanGloss,
        arabicText: cachedResult.arabicText,
        isFromCache: true,
        totalLatencyMs: 0,
        firstTokenMs: 0,
        tokensPerSec: 0,
        timestamp: DateTime.now(),
      );
    }

    // 2. إذا كان النموذج غير جاهز، نحاول تجهيزه دون تجميد
    if (!isReady) {
      final ok = await loadModel();
      if (!ok) return null;
    }

    // 3. منع تداخل الاستنتاج (Inference Overlap Prevention)
    if (_state == GlossModelState.generating) {
      if (kDebugMode) {
        debugPrint('[GlossModelService] Already generating. Overriding pending gloss with: "$cleanGloss"');
      }
      // إيقاف التوليد القديم الذي أصبح غير صالح
      await stopGeneration();
      _pendingGloss = cleanGloss;
      return null;
    }

    _setState(GlossModelState.generating);
    final completer = Completer<GlossResult?>();
    _currentCompleter = completer;

    // تجهيز الـ Prompt القصير المطابق لطريقة تدريب النموذج
    final prompt = 'Translate ArSL gloss to an MSA sentence.\nGloss: $cleanGloss\nOutput:';

    final buffer = StringBuffer();
    final stopwatch = Stopwatch()..start();
    int firstTokenLatencyMs = 0;
    int tokenCount = 0;

    try {
      if (Platform.isAndroid && _llamaController != null) {
        // الاستنتاج الفعلي عبر llama_flutter_android
        _generationSubscription = _llamaController!
            .generate(
              prompt: prompt,
              maxTokens: 48,
              temperature: 0.1, // درجة حرارة منخفضة لترجمة ثابتة ومستقرة
              topP: 0.9,
              repeatPenalty: 1.15,
            )
            .listen(
              (token) {
                if (firstTokenLatencyMs == 0) {
                  firstTokenLatencyMs = stopwatch.elapsedMilliseconds;
                }
                tokenCount++;
                buffer.write(token);
              },
              onDone: () {
                stopwatch.stop();
                final totalTimeMs = stopwatch.elapsedMilliseconds;
                final tps = totalTimeMs > 0 ? (tokenCount * 1000.0) / totalTimeMs : 0.0;

                _lastFirstTokenMs = firstTokenLatencyMs;
                _lastTotalDurationMs = totalTimeMs;
                _lastTokensPerSec = tps;

                final rawOutput = buffer.toString();
                final cleanOutput = _cleanOutput(rawOutput, cleanGloss);

                final result = GlossResult(
                  gloss: cleanGloss,
                  arabicText: cleanOutput,
                  isFromCache: false,
                  totalLatencyMs: totalTimeMs,
                  firstTokenMs: firstTokenLatencyMs,
                  tokensPerSec: tps,
                  timestamp: DateTime.now(),
                );

                // حفظ النتيجة في الـ In-Memory Cache
                _cache[cacheKey] = result;

                if (kDebugMode) {
                  debugPrint('[GlossModelService] Generation complete: "$cleanOutput" (${totalTimeMs}ms, ${tps.toStringAsFixed(1)} t/s)');
                }

                _setState(GlossModelState.ready);
                if (!completer.isCompleted) {
                  completer.complete(result);
                }
                _handlePendingGloss();
              },
              onError: (error) {
                stopwatch.stop();
                if (kDebugMode) {
                  debugPrint('[GlossModelService] Generation error: $error');
                }
                _setState(GlossModelState.ready);
                if (!completer.isCompleted) {
                  completer.complete(null);
                }
                _handlePendingGloss();
              },
            );
      } else {
        // Fallback للمحاكاة خارج بيئة Android الحقيقية
        await Future.delayed(const Duration(milliseconds: 150));
        final fallbackSentence = _simulateTranslation(cleanGloss);
        final result = GlossResult(
          gloss: cleanGloss,
          arabicText: fallbackSentence,
          isFromCache: false,
          totalLatencyMs: 150,
          firstTokenMs: 50,
          tokensPerSec: 25.0,
          timestamp: DateTime.now(),
        );
        _cache[cacheKey] = result;
        _setState(GlossModelState.ready);
        completer.complete(result);
        _handlePendingGloss();
      }
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) debugPrint('[GlossModelService] Translate error: $e');
      _setState(GlossModelState.ready);
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      _handlePendingGloss();
    }

    return completer.future;
  }

  void _handlePendingGloss() {
    if (_pendingGloss != null) {
      final next = _pendingGloss!;
      _pendingGloss = null;
      Future.microtask(() => translateGloss(next));
    }
  }

  /// تنظيف وتنسيق مخرجات النموذج
  String _cleanOutput(String output, String originalGloss) {
    String text = output.trim();
    // إزالة تكرار كلمة Output: إن وُجدت
    if (text.startsWith('Output:')) {
      text = text.substring(7).trim();
    }
    // إزالة علامات الاقتباس المحيطة
    text = text.replaceAll(RegExp(r'^["«]+|["»]+$'), '').trim();
    // إزالة أي أسطر فارغة متكررة
    text = text.split('\n').first.trim();

    if (text.isEmpty) {
      return originalGloss;
    }
    // إضافة نقطة نهاية إن لم تكن الجملة منتهية
    if (!text.endsWith('.') && !text.endsWith('!') && !text.endsWith('؟')) {
      text = '$text.';
    }
    return text;
  }

  /// محاكاة محلية ذكية خارج بيئة Android
  String _simulateTranslation(String gloss) {
    if (gloss.contains('أنا') && gloss.contains('ذهاب') && gloss.contains('سوق')) {
      return 'أنا ذاهب إلى السوق.';
    }
    if (gloss.contains('أنا') && gloss.contains('ماء')) {
      return 'أنا أريد شرب الماء.';
    }
    if (gloss.contains('أنت') && gloss.contains('مساعدة')) {
      return 'هل يمكنك مساعدتي؟';
    }
    return '$gloss.';
  }

  // ────────────────────────────────── 4. إيقاف وتفريغ ──────────────────────────────────

  /// إلغاء التوليد الجاري فوراً
  Future<void> stopGeneration() async {
    try {
      await _generationSubscription?.cancel();
      _generationSubscription = null;
      if (_llamaController != null && Platform.isAndroid) {
        await _llamaController!.stop();
      }
    } catch (_) {}
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete(null);
    }
    _setState(GlossModelState.ready);
  }

  void _setState(GlossModelState newState) {
    _state = newState;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _state = GlossModelState.error;
    if (kDebugMode) debugPrint('[GlossModelService] Error: $message');
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await stopGeneration();
    try {
      await _llamaController?.dispose();
    } catch (_) {}
    _llamaController = null;
    _cache.clear();
    super.dispose();
  }
}
