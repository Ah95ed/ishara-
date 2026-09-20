import 'package:flutter/services.dart';
import 'package:ishara/ml/buffer/ishara_frame_ring_buffer.dart';
import 'package:ishara/ml/ctc/ishara_ctc_decoder.dart';
import 'package:ishara/ml/model/ishara_tflite_service.dart';
import 'package:ishara/models/ctc_vocab_result.dart';
import 'package:ishara/models/real_inference_result.dart';
import 'package:ishara/services/vision_detection_service.dart';

/// RealInferenceTestService
/// خدمة تنفيذ اختبارات الاستنتاج للتسلسلات الحقيقية ومقارنة الحركات (A / B Motion Test)
/// تعمل بصرامة تامة دون: CTC، Vocabulary، Gloss، أو تعديل الـ Pipeline الأساسي.
class RealInferenceTestService {
  final VisionDetectionService _visionService;

  SingleRealInferenceResult? _resultA;
  SingleRealInferenceResult? _resultB;
  RealInferenceComparisonResult? _comparison;

  int? _testASequenceId;
  bool _isInferenceRunning = false;

  RealInferenceTestService(this._visionService);

  SingleRealInferenceResult? get resultA => _resultA;
  SingleRealInferenceResult? get resultB => _resultB;
  RealInferenceComparisonResult? get comparison => _comparison;
  bool get isInferenceRunning => _isInferenceRunning;
  int? get testASequenceId => _testASequenceId;

  IsharaFrameRingBuffer get _ringBuffer => _visionService.ringBuffer;
  IsharaTfliteService get _tfliteService => _visionService.tfliteService;

  /// حساب عدد الإطارات الجديدة المضافة للـ Ring Buffer منذ التقاط Test A (0..128)
  int get newFramesSinceTestA {
    if (_testASequenceId == null) return 128;
    final status = _ringBuffer.getStatus();
    final latestId = status.latestFrameSequenceId;
    if (latestId == null) return 0;
    final diff = latestId - _testASequenceId!;
    return diff.clamp(0, 128);
  }

  /// هل تم تدوير الـ Buffer بالكامل (128 إطاراً جديداً) ومستعد لالتقاط Test B؟
  bool get isReadyForTestB => _resultA != null && newFramesSinceTestA >= 128;

  /// التقاط عينة واستنتاج تسلسل حقيقي لـ Test A أو Test B
  Future<SingleRealInferenceResult> captureAndInfer({required String testLabel}) async {
    final now = DateTime.now();

    if (_isInferenceRunning) {
      return SingleRealInferenceResult.failure(
        testLabel: testLabel,
        capturedAt: now,
        errorCode: 'E_CONCURRENT_INFERENCE',
        errorMessage: 'An inference operation is already running',
      );
    }
    _isInferenceRunning = true;

    try {
      // 1. التحقق من جاهزية الـ Ring Buffer (128/128)
      if (!_ringBuffer.isReady) {
        return SingleRealInferenceResult.failure(
          testLabel: testLabel,
          capturedAt: now,
          bufferCount: _ringBuffer.count,
          errorCode: 'E_BUFFER_NOT_READY',
          errorMessage: 'Buffer not full: ${_ringBuffer.count}/128 frames',
        );
      }

      // 2. أخذ Snapshot عميق وغير قابل للتعديل (Immutable Deep Copy)
      final inputSequence = _ringBuffer.buildModelInput(applyHandsBackwardFill: true);
      if (inputSequence == null) {
        return SingleRealInferenceResult.failure(
          testLabel: testLabel,
          capturedAt: now,
          errorCode: 'E_BUFFER_SNAPSHOT_FAILED',
          errorMessage: 'Failed to extract snapshot from Ring Buffer',
        );
      }

      // 3. أخذ تقرير الجودة الشامل لنفس الـ Snapshot
      final quality = _ringBuffer.analyzeCurrentSequence(captureTime: now);

      // 4. التحقق الصارم قبل إرسال البيانات للموديل
      if (inputSequence.shape.length != 4 ||
          inputSequence.shape[0] != 1 ||
          inputSequence.shape[1] != 128 ||
          inputSequence.shape[2] != 86 ||
          inputSequence.shape[3] != 2) {
        return SingleRealInferenceResult.failure(
          testLabel: testLabel,
          capturedAt: now,
          bufferCount: inputSequence.frameCount,
          inputShape: inputSequence.shape,
          errorCode: 'E_REAL_INPUT_SHAPE',
          errorMessage: 'Invalid real input shape: ${inputSequence.shape} (Expected [1,128,86,2])',
        );
      }

      if (inputSequence.nanCount > 0) {
        return SingleRealInferenceResult.failure(
          testLabel: testLabel,
          capturedAt: now,
          bufferCount: inputSequence.frameCount,
          inputShape: inputSequence.shape,
          inputNanCount: inputSequence.nanCount,
          errorCode: 'E_REAL_INPUT_NAN',
          errorMessage: 'Real input contains ${inputSequence.nanCount} NaN values',
        );
      }

      if (inputSequence.infCount > 0) {
        return SingleRealInferenceResult.failure(
          testLabel: testLabel,
          capturedAt: now,
          bufferCount: inputSequence.frameCount,
          inputShape: inputSequence.shape,
          inputInfCount: inputSequence.infCount,
          errorCode: 'E_REAL_INPUT_INF',
          errorMessage: 'Real input contains ${inputSequence.infCount} Infinity values',
        );
      }

      // التحقق الزمني Chronological Check (Oldest -> Newest)
      final bool isChronological = inputSequence.newestFrameSequenceId >= inputSequence.oldestFrameSequenceId;
      if (!isChronological) {
        return SingleRealInferenceResult.failure(
          testLabel: testLabel,
          capturedAt: now,
          bufferCount: inputSequence.frameCount,
          inputShape: inputSequence.shape,
          isChronological: false,
          errorCode: 'E_REAL_INPUT_CHRONOLOGICAL',
          errorMessage: 'Frames are not strictly ordered chronologically',
        );
      }

      // 5. تشغيل الاستنتاج على نفس الـ Interpreter المشترك
      final rawOutput = await _tfliteService.runRealSequenceInference(inputSequence);

      if (!rawOutput.isSuccess) {
        return SingleRealInferenceResult.failure(
          testLabel: testLabel,
          capturedAt: now,
          bufferCount: inputSequence.frameCount,
          inputShape: inputSequence.shape,
          inputNanCount: inputSequence.nanCount,
          inputInfCount: inputSequence.infCount,
          isChronological: isChronological,
          oldestFrameSequenceId: inputSequence.oldestFrameSequenceId,
          newestFrameSequenceId: inputSequence.newestFrameSequenceId,
          rawKeypointCoveragePct: quality.rawCoveragePercent,
          imputationPct: quality.imputationPercent,
          rightHandCoveragePct: quality.rhCoveragePercent,
          leftHandCoveragePct: quality.lhCoveragePercent,
          lipsCoveragePct: quality.lipsCoveragePercent,
          bodyCoveragePct: quality.bodyCoveragePercent,
          errorCode: rawOutput.errorCode ?? 'E_INFERENCE_FAILED',
          errorMessage: rawOutput.errorMessage ?? 'Interpreter execution failed',
        );
      }

      final result = SingleRealInferenceResult(
        testLabel: testLabel,
        capturedAt: now,
        isSuccess: true,
        inferenceTimeMs: rawOutput.inferenceTimeMs,
        bufferCount: inputSequence.frameCount,
        inputShape: inputSequence.shape,
        inputNanCount: inputSequence.nanCount,
        inputInfCount: inputSequence.infCount,
        isChronological: isChronological,
        oldestFrameSequenceId: inputSequence.oldestFrameSequenceId,
        newestFrameSequenceId: inputSequence.newestFrameSequenceId,
        rawKeypointCoveragePct: quality.rawCoveragePercent,
        imputationPct: quality.imputationPercent,
        rightHandCoveragePct: quality.rhCoveragePercent,
        leftHandCoveragePct: quality.lhCoveragePercent,
        lipsCoveragePct: quality.lipsCoveragePercent,
        bodyCoveragePct: quality.bodyCoveragePercent,
        outputShape: rawOutput.outputShape,
        outputNanCount: rawOutput.nanCount,
        outputInfCount: rawOutput.infCount,
        outputMin: rawOutput.outputMin,
        outputMax: rawOutput.outputMax,
        outputMean: rawOutput.outputMean,
        outputStdDev: rawOutput.outputStdDev,
        rawArgmax: rawOutput.rawArgmax,
        uniqueClasses: rawOutput.uniqueClasses,
        blankTop1Count: rawOutput.blankTop1Count,
        flatOutput: rawOutput.flatOutput,
        ctcResult: IsharaCtcDecoder.decodeRawArgmax(
          rawOutput.rawArgmax,
          capturedAt: now,
          nanCount: rawOutput.nanCount,
          infCount: rawOutput.infCount,
        ),
      );

      final fullResult = SingleRealInferenceResult(
        testLabel: result.testLabel,
        capturedAt: result.capturedAt,
        isSuccess: result.isSuccess,
        errorCode: result.errorCode,
        errorMessage: result.errorMessage,
        inferenceTimeMs: result.inferenceTimeMs,
        bufferCount: result.bufferCount,
        inputShape: result.inputShape,
        inputNanCount: result.inputNanCount,
        inputInfCount: result.inputInfCount,
        isChronological: result.isChronological,
        oldestFrameSequenceId: result.oldestFrameSequenceId,
        newestFrameSequenceId: result.newestFrameSequenceId,
        rawKeypointCoveragePct: result.rawKeypointCoveragePct,
        imputationPct: result.imputationPct,
        rightHandCoveragePct: result.rightHandCoveragePct,
        leftHandCoveragePct: result.leftHandCoveragePct,
        lipsCoveragePct: result.lipsCoveragePct,
        bodyCoveragePct: result.bodyCoveragePct,
        outputShape: result.outputShape,
        outputNanCount: result.outputNanCount,
        outputInfCount: result.outputInfCount,
        outputMin: result.outputMin,
        outputMax: result.outputMax,
        outputMean: result.outputMean,
        outputStdDev: result.outputStdDev,
        rawArgmax: result.rawArgmax,
        uniqueClasses: result.uniqueClasses,
        blankTop1Count: result.blankTop1Count,
        flatOutput: result.flatOutput,
        ctcResult: result.ctcResult,
        ctcVocabResult: runCtcVocabDecoding(result),
      );

      // حفظ النتيجة وتحديث الحالة
      if (testLabel == 'TEST A') {
        _resultA = fullResult;
        _testASequenceId = inputSequence.newestFrameSequenceId;
        _resultB = null;
        _comparison = null;
      } else {
        _resultB = fullResult;
        if (_resultA != null && _resultA!.isSuccess) {
          _comparison = RealInferenceComparisonResult.compare(_resultA!, fullResult);
        }
      }

      return fullResult;
    } catch (e) {
      final fail = SingleRealInferenceResult.failure(
        testLabel: testLabel,
        capturedAt: now,
        errorCode: 'E_UNEXPECTED_ERROR',
        errorMessage: 'Unexpected error during real inference: $e',
      );
      if (testLabel == 'TEST A') {
        _resultA = fail;
      } else {
        _resultB = fail;
      }
      return fail;
    } finally {
      _isInferenceRunning = false;
    }
  }

  /// إعادة تعيين عداد نافذة الاختبار الجديد
  void startNewTestWindow() {
    final status = _ringBuffer.getStatus();
    _testASequenceId = status.latestFrameSequenceId;
    _resultB = null;
    _comparison = null;
  }

  /// تصفير الجلسة بالكامل
  void resetSession() {
    _resultA = null;
    _resultB = null;
    _comparison = null;
    _testASequenceId = null;
  }

  /// الحصول على الجلسة الحالية
  RealInferenceSession getSession() {
    return RealInferenceSession(
      testA: _resultA,
      testB: _resultB,
      comparison: _comparison,
      framesSinceTestA: newFramesSinceTestA,
      isInferenceRunning: _isInferenceRunning,
    );
  }

  /// توليد التقرير النصي الرسمي
  String generateReport() {
    final status = _tfliteService.getStatus();
    return getSession().toReportText(
      modelName: 'ishara_model.tflite',
      modelSize: status.modelSizeMb > 0 ? '${status.modelSizeMb.toStringAsFixed(2)} MB' : '107.55 MB',
      interpreterStatus: _tfliteService.isReady ? 'READY' : 'NOT_READY',
    );
  }

  /// نسخ التقرير إلى الحافظة
  Future<String> copyReportToClipboard() async {
    final report = generateReport();
    await Clipboard.setData(ClipboardData(text: report));
    return report;
  }

  /// توليد تقرير فك تشفير CTC
  String generateCtcReport({String testLabel = 'TEST A'}) {
    final ctc = (testLabel == 'TEST B') ? _resultB?.ctcResult : _resultA?.ctcResult;
    if (ctc != null) {
      return ctc.toReportText();
    }
    // إذا لم يتوفر بعد، نولد تقرير افتراضي
    return IsharaCtcDecoder.decodeRawArgmax(const []).toReportText();
  }

  /// نسخ تقرير CTC إلى الحافظة
  Future<String> copyCtcReportToClipboard({String testLabel = 'TEST A'}) async {
    final report = generateCtcReport(testLabel: testLabel);
    await Clipboard.setData(ClipboardData(text: report));
    return report;
  }

  /// فك التشفير وربط المفردات لاستنتاج حقيقي محدد (Test A أو Test B)
  CtcVocabResult runCtcVocabDecoding(SingleRealInferenceResult? inferenceResult) {
    if (inferenceResult == null || !inferenceResult.isSuccess) {
      return CtcVocabResult.failure(
        testLabel: inferenceResult?.testLabel ?? 'NO_TEST',
        errorCode: 'E_NO_REAL_INFERENCE',
        errorMessage: 'NO_REAL_INFERENCE_AVAILABLE',
        capturedAt: DateTime.now(),
        vocabFile: _visionService.vocabService.assetPath,
        isVocabLoaded: _visionService.vocabService.isLoaded,
        vocabEntries: _visionService.vocabService.entriesCount,
      );
    }

    final ctc = inferenceResult.ctcResult ??
        IsharaCtcDecoder.decodeRawArgmax(
          inferenceResult.rawArgmax,
          capturedAt: inferenceResult.capturedAt,
          nanCount: inferenceResult.outputNanCount,
          infCount: inferenceResult.outputInfCount,
        );

    final vocabService = _visionService.vocabService;
    final vocabValidation = vocabService.validateDecodedIds(ctc.decodedIds);

    final predictedGlosses = <GlossItem>[];
    final finalGlossSequence = <String>[];
    for (final id in ctc.decodedIds) {
      final gloss = vocabService.getGloss(id);
      predictedGlosses.add(GlossItem(classId: id, gloss: gloss));
      finalGlossSequence.add(gloss);
    }

    final bool isOutputShapePass = inferenceResult.outputShape.length == 3 &&
        inferenceResult.outputShape[0] == 1 &&
        inferenceResult.outputShape[1] == 29 &&
        inferenceResult.outputShape[2] == 684;

    return CtcVocabResult(
      testLabel: inferenceResult.testLabel,
      capturedAt: inferenceResult.capturedAt,
      isSuccess: true,
      outputShape: inferenceResult.outputShape,
      classesCount: 684,
      blankId: 0,
      sequenceQualityPct: inferenceResult.rawKeypointCoveragePct,
      imputationPct: inferenceResult.imputationPct,
      ctcResult: ctc,
      vocabFile: vocabService.assetPath,
      isVocabLoaded: vocabService.isLoaded,
      vocabEntries: vocabService.entriesCount,
      blankHandlingPass: vocabValidation.blankHandlingPass,
      missingIds: vocabValidation.missingIds,
      predictedGlosses: predictedGlosses,
      finalGlossSequence: finalGlossSequence,
      ctcUnitTestsPass: IsharaCtcDecoder.runSelfTests(),
      isOutputShapePass: isOutputShapePass,
      isIdRangePass: ctc.isIdsRangeValid,
      isVocabMappingPass: vocabValidation.isPass,
      nanCount: inferenceResult.outputNanCount,
      infCount: inferenceResult.outputInfCount,
    );
  }

  /// الحصول على تقرير CTC + Vocab لـ Test A أو Test B
  String generateCtcVocabReport({String testLabel = 'TEST A'}) {
    final result = (testLabel == 'TEST B') ? _resultB : _resultA;
    final ctcVocab = result?.ctcVocabResult ?? runCtcVocabDecoding(result);
    return ctcVocab.toReportText();
  }

  /// نسخ تقرير CTC + Vocab الكامل المطابق للمواصفات
  Future<String> copyCtcVocabReportToClipboard({String testLabel = 'TEST A'}) async {
    final report = generateCtcVocabReport(testLabel: testLabel);
    await Clipboard.setData(ClipboardData(text: report));
    return report;
  }
}
