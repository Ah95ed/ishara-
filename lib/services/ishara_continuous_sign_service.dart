import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara/ml/activity/ishara_sign_activity_detector.dart';
import 'package:ishara/ml/buffer/ishara_frame_ring_buffer.dart';
import 'package:ishara/ml/ctc/ishara_ctc_decoder.dart';
import 'package:ishara/ml/model/ishara_tflite_service.dart';
import 'package:ishara/ml/temporal/ishara_temporal_stability_tracker.dart';
import 'package:ishara/ml/vocab/ishara_vocab_service.dart';

/// نتيجة التقرير الشامل لتمييز الإشارات المستمرة
class SignRecognitionReportData {
  final DateTime capturedAt;
  final int bufferCount;
  final double qualityPct;
  final double imputationPct;
  final double rhCoveragePct;
  final double lhCoveragePct;
  final double lipsCoveragePct;
  final double bodyCoveragePct;
  final bool startDetected;
  final String startTimeStr;
  final bool endDetected;
  final String endTimeStr;
  final int durationMs;
  final double motionBaseline;
  final double peakMotion;
  final int slidingStride;
  final int inferenceAttempts;
  final int inferenceExecuted;
  final int inferenceSkippedBusy;
  final double averageInferenceTimeMs;
  final List<WindowCandidate> candidates;
  final int votes;
  final List<int> stableIds;
  final bool stabilityPass;
  final bool isAccepted;
  final List<int> acceptedIds;
  final List<String> acceptedGlosses;
  final double sequenceConfidence;
  final String reasonCode;
  final int nanCount;
  final int infCount;
  final bool modelPass;
  final bool ctcPass;
  final bool vocabPass;
  final bool pipelinePass;

  const SignRecognitionReportData({
    required this.capturedAt,
    required this.bufferCount,
    required this.qualityPct,
    required this.imputationPct,
    required this.rhCoveragePct,
    required this.lhCoveragePct,
    required this.lipsCoveragePct,
    required this.bodyCoveragePct,
    required this.startDetected,
    required this.startTimeStr,
    required this.endDetected,
    required this.endTimeStr,
    required this.durationMs,
    required this.motionBaseline,
    required this.peakMotion,
    required this.slidingStride,
    required this.inferenceAttempts,
    required this.inferenceExecuted,
    required this.inferenceSkippedBusy,
    required this.averageInferenceTimeMs,
    required this.candidates,
    required this.votes,
    required this.stableIds,
    required this.stabilityPass,
    required this.isAccepted,
    required this.acceptedIds,
    required this.acceptedGlosses,
    required this.sequenceConfidence,
    required this.reasonCode,
    required this.nanCount,
    required this.infCount,
    required this.modelPass,
    required this.ctcPass,
    required this.vocabPass,
    required this.pipelinePass,
  });

  /// توليد التقرير النصي المطابق حرفياً لمواصفات البند 28
  String toReportText() {
    final buf = StringBuffer();
    final timeStr = capturedAt
        .toIso8601String()
        .replaceFirst('T', ' ')
        .substring(0, 19);

    buf.writeln('================================');
    buf.writeln('ISHARA SIGN RECOGNITION REPORT');
    buf.writeln('================================');
    buf.writeln('');
    buf.writeln('Captured At:');
    buf.writeln(timeStr);
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('SEQUENCE');
    buf.writeln('');
    buf.writeln('Buffer:');
    buf.writeln('$bufferCount/128');
    buf.writeln('');
    buf.writeln('Quality:');
    buf.writeln('${qualityPct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('Imputation:');
    buf.writeln('${imputationPct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('RH Coverage:');
    buf.writeln('${rhCoveragePct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('LH Coverage:');
    buf.writeln('${lhCoveragePct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('Lips Coverage:');
    buf.writeln('${lipsCoveragePct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('Body Coverage:');
    buf.writeln('${bodyCoveragePct.toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('SIGN ACTIVITY');
    buf.writeln('');
    buf.writeln('Start Detected:');
    buf.writeln(startDetected ? 'YES' : 'NO');
    buf.writeln('');
    buf.writeln('Start Time:');
    buf.writeln(startTimeStr);
    buf.writeln('');
    buf.writeln('End Detected:');
    buf.writeln(endDetected ? 'YES' : 'NO');
    buf.writeln('');
    buf.writeln('End Time:');
    buf.writeln(endTimeStr);
    buf.writeln('');
    buf.writeln('Duration:');
    buf.writeln('$durationMs ms');
    buf.writeln('');
    buf.writeln('Motion Baseline:');
    buf.writeln(motionBaseline.toStringAsFixed(4));
    buf.writeln('');
    buf.writeln('Peak Motion:');
    buf.writeln(peakMotion.toStringAsFixed(4));
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('INFERENCE');
    buf.writeln('');
    buf.writeln('Sliding Stride:');
    buf.writeln('$slidingStride frames');
    buf.writeln('');
    buf.writeln('Inference Attempts:');
    buf.writeln('$inferenceAttempts');
    buf.writeln('');
    buf.writeln('Inference Executed:');
    buf.writeln('$inferenceExecuted');
    buf.writeln('');
    buf.writeln('Inference Skipped Busy:');
    buf.writeln('$inferenceSkippedBusy');
    buf.writeln('');
    buf.writeln('Average Inference Time:');
    buf.writeln('${averageInferenceTimeMs.toStringAsFixed(1)} ms');
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('CANDIDATES');
    buf.writeln('');

    if (candidates.isEmpty) {
      buf.writeln('None');
    } else {
      for (int i = 0; i < 3; i++) {
        final wIdx = i + 1;
        buf.writeln('Window $wIdx:');
        buf.writeln('');
        if (i < candidates.length) {
          final c = candidates[i];
          buf.writeln('CTC IDs:');
          buf.writeln('[${c.decodedIds.join(',')}]');
          buf.writeln('');
          buf.writeln('Glosses:');
          buf.writeln('[${c.glosses.join(', ')}]');
          buf.writeln('');
          buf.writeln('Sequence Confidence:');
          buf.writeln('${(c.sequenceConfidence * 100).toStringAsFixed(2)} %');
        } else {
          buf.writeln('CTC IDs:');
          buf.writeln('[]');
          buf.writeln('');
          buf.writeln('Glosses:');
          buf.writeln('[]');
          buf.writeln('');
          buf.writeln('Sequence Confidence:');
          buf.writeln('0.00 %');
        }
        if (i < 2) buf.writeln('');
      }
    }

    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('STABILITY');
    buf.writeln('');
    buf.writeln('Votes:');
    buf.writeln('');
    buf.writeln('[${stableIds.join(',')}] = $votes / 3');
    buf.writeln('');
    buf.writeln('Stable Candidate:');
    buf.writeln('[${stableIds.join(',')}]');
    buf.writeln('');
    buf.writeln('Stability:');
    buf.writeln(stabilityPass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('FINAL ACCEPTANCE');
    buf.writeln('');
    buf.writeln('Accepted:');
    buf.writeln(isAccepted ? 'YES' : 'NO');
    buf.writeln('');
    buf.writeln('IDs:');
    buf.writeln('[${acceptedIds.join(',')}]');
    buf.writeln('');
    buf.writeln('Glosses:');
    buf.writeln('[${acceptedGlosses.join(', ')}]');
    buf.writeln('');
    buf.writeln('Sequence Confidence:');
    buf.writeln('${(sequenceConfidence * 100).toStringAsFixed(2)} %');
    buf.writeln('');
    buf.writeln('Reason:');
    buf.writeln('');
    buf.writeln(reasonCode);
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('VALIDATION');
    buf.writeln('');
    buf.writeln('NaN:');
    buf.writeln('$nanCount');
    buf.writeln('');
    buf.writeln('Infinity:');
    buf.writeln('$infCount');
    buf.writeln('');
    buf.writeln('Model:');
    buf.writeln(modelPass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('CTC:');
    buf.writeln(ctcPass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('Vocabulary:');
    buf.writeln(vocabPass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('--------------------------------');
    buf.writeln('');
    buf.writeln('FINAL RESULT');
    buf.writeln('');
    buf.writeln('SIGN RECOGNITION PIPELINE:');
    buf.writeln(pipelinePass ? 'PASS' : 'FAIL');
    buf.writeln('');
    buf.writeln('================================');

    return buf.toString();
  }
}

/// IsharaContinuousSignService
/// منسق خط المعالجة الزمني الشامل لتمييز إشارات لغة الإشارة المستمرة:
/// 1. مراقبة الحركة وبداية/نهاية الإشارة عبر IsharaSignActivityDetector
/// 2. أخذ لقطات مستقلة من الـ 128 Frame Ring Buffer
/// 3. استنتاج انزلاقي كل 8 إطارات مع قفل صارم يمنع التزامن وتراكم الطوابير
/// 4. فك تشفير CTC وربط المفردات واستخراج الثقة (Softmax + Margin)
/// 5. التحقق من الاستقرار الزمني 2/3 ومنع التكرار داخل المقطع الحركي
class IsharaContinuousSignService extends ChangeNotifier {
  final IsharaFrameRingBuffer ringBuffer;
  final IsharaTfliteService tfliteService;
  final IsharaVocabService vocabService;

  final IsharaSignActivityDetector activityDetector = IsharaSignActivityDetector();
  final IsharaTemporalStabilityTracker stabilityTracker = IsharaTemporalStabilityTracker();

  int slidingStrideFrames = 8;
  int _lastInferenceFrameSeqId = 0;
  bool _isInferring = false;
  bool _isTestActive = false;

  // إحصائيات الأداء والاستنتاج
  int _inferenceAttempts = 0;
  int _inferenceExecuted = 0;
  int _inferenceSkippedBusy = 0;
  int _totalInferenceTimeMs = 0;

  // النتائج الحالية المعتمدة
  TemporalStabilityEvaluation? _latestEvaluation;
  SignActivityDiagnostic? _latestActivity;
  List<String> _acceptedGlosses = [];
  String _displayStatus = 'WAITING'; // WAITING, SIGNING, PROCESSING

  IsharaContinuousSignService({
    required this.ringBuffer,
    required this.tfliteService,
    required this.vocabService,
  });

  bool get isInferring => _isInferring;
  bool get isTestActive => _isTestActive;
  String get displayStatus => _displayStatus;
  List<String> get acceptedGlosses => _acceptedGlosses;
  TemporalStabilityEvaluation? get latestEvaluation => _latestEvaluation;
  SignActivityDiagnostic? get latestActivity => _latestActivity;
  int get inferenceAttempts => _inferenceAttempts;
  int get inferenceExecuted => _inferenceExecuted;
  int get inferenceSkippedBusy => _inferenceSkippedBusy;
  double get averageInferenceTimeMs =>
      _inferenceExecuted > 0 ? (_totalInferenceTimeMs / _inferenceExecuted) : 0.0;

  /// بدء جلسة فحص واختبار التمييز المستمر
  void startTest() {
    _isTestActive = true;
    _acceptedGlosses.clear();
    _inferenceAttempts = 0;
    _inferenceExecuted = 0;
    _inferenceSkippedBusy = 0;
    _totalInferenceTimeMs = 0;
    _lastInferenceFrameSeqId = 0;
    activityDetector.reset();
    stabilityTracker.reset();
    _displayStatus = 'WAITING';
    notifyListeners();
  }

  /// إيقاف جلسة الاختبار
  void stopTest() {
    _isTestActive = false;
    _displayStatus = 'IDLE';
    notifyListeners();
  }

  /// يتم استدعاؤها مع كل إطار يدخل الـ Ring Buffer
  Future<void> onFrameIngested(IsharaBufferFrame frame) async {
    // 1. تحديث كاشف نشاط الإشارة
    _latestActivity = activityDetector.processFrame(frame);

    // تحديث نص الحالة المعروض في الشاشة
    if (_isInferring) {
      _displayStatus = 'PROCESSING';
    } else if (_latestActivity!.state == SignActivityState.signing) {
      _displayStatus = 'SIGNING';
    } else {
      _displayStatus = 'WAITING';
    }

    if (!_isTestActive) {
      notifyListeners();
      return;
    }

    // 2. التحقق من اكتمال الـ Buffer (128/128)
    if (!ringBuffer.isReady) {
      notifyListeners();
      return;
    }

    // 3. التحقق من انقضاء الـ Stride (كل 8 إطارات جديدة)
    final frameId = frame.sequenceId;
    if (frameId - _lastInferenceFrameSeqId < slidingStrideFrames) {
      notifyListeners();
      return;
    }

    // 4. لا نشغل الاستنتاج إذا كان المستخدم في وضع السكون الكامل (No-motion behavior)
    final bool isActivityActive = _latestActivity!.state == SignActivityState.signing ||
        _latestActivity!.state == SignActivityState.ending ||
        _latestActivity!.state == SignActivityState.ready;

    if (!isActivityActive) {
      notifyListeners();
      return;
    }

    // 5. حماية التزامن الصارمة: إذا كان الموديل مشغولاً نتجاهل التريجر (Latest data wins)
    _inferenceAttempts++;
    if (_isInferring) {
      _inferenceSkippedBusy++;
      notifyListeners();
      return;
    }

    _lastInferenceFrameSeqId = frameId;
    await _executeSlidingInference(frame.timestamp);
  }

  /// تنفيذ استنتاج انزلاقي آمن على لقطة مستقلة
  Future<void> _executeSlidingInference(DateTime timestamp) async {
    _isInferring = true;
    _displayStatus = 'PROCESSING';
    notifyListeners();

    try {
      final startTime = DateTime.now();

      // أخذ لقطة عميقة غير قابلة للتعديل من الـ Ring Buffer
      final inputSequence = ringBuffer.buildModelInput(applyHandsBackwardFill: true);
      if (inputSequence == null) {
        _isInferring = false;
        return;
      }

      final quality = ringBuffer.analyzeCurrentSequence(captureTime: timestamp);

      // تشغيل استنتاج TFLite
      final rawOutput = await tfliteService.runRealSequenceInference(inputSequence);
      final inferenceTime = DateTime.now().difference(startTime).inMilliseconds;
      _totalInferenceTimeMs += inferenceTime;
      _inferenceExecuted++;

      if (rawOutput.isSuccess) {
        // فك تشفير CTC مع استخراج الثقة لكل رمز
        final ctcResult = IsharaCtcDecoder.decodeRawArgmax(
          rawOutput.rawArgmax,
          capturedAt: timestamp,
          nanCount: rawOutput.nanCount,
          infCount: rawOutput.infCount,
        );

        // ربط المفردات
        final glosses = vocabService.mapIdsToGlosses(ctcResult.decodedIds);

        // تقييم الاستقرار الزمني 2/3 ومنع التكرار داخل المقطع
        final evaluation = stabilityTracker.registerInferenceWindow(
          decodedIds: ctcResult.decodedIds,
          glosses: glosses,
          sequenceConfidence: ctcResult.diagnosticSequenceConfidence,
          quality: quality,
          currentSignSegmentId: activityDetector.signSegmentId,
          isSigningActive: true,
          timestamp: timestamp,
        );

        _latestEvaluation = evaluation;

        if (evaluation.isAccepted && evaluation.stableGlosses.isNotEmpty) {
          _acceptedGlosses = List<String>.from(evaluation.stableGlosses);
        }
      }
    } catch (e) {
      debugPrint('[IsharaContinuousSignService] ⚠️ Inference error: $e');
    } finally {
      _isInferring = false;
      _displayStatus = activityDetector.state == SignActivityState.signing ? 'SIGNING' : 'WAITING';
      notifyListeners();
    }
  }

  /// توليد التقرير التشخيصي الرسمي لتمييز الإشارات
  SignRecognitionReportData generateReportData() {
    final now = DateTime.now();
    final quality = ringBuffer.analyzeCurrentSequence(captureTime: now);
    final eval = _latestEvaluation;
    final candidates = stabilityTracker.windowHistory;

    final start = activityDetector.signStartTime;
    final end = activityDetector.signEndTime;

    final startTimeStr = start != null
        ? start.toIso8601String().replaceFirst('T', ' ').substring(11, 19)
        : 'NONE';
    final endTimeStr = end != null
        ? end.toIso8601String().replaceFirst('T', ' ').substring(11, 19)
        : 'NONE';

    final bool isAccepted = eval?.isAccepted ?? false;
    final List<int> stableIds = eval?.stableIds ?? (candidates.isNotEmpty ? candidates.last.decodedIds : const []);
    final int votes = eval?.votes ?? (candidates.isNotEmpty ? 1 : 0);
    final bool stabilityPass = votes >= 2;

    return SignRecognitionReportData(
      capturedAt: now,
      bufferCount: ringBuffer.count,
      qualityPct: quality.rawCoveragePercent,
      imputationPct: quality.imputationPercent,
      rhCoveragePct: quality.rhCoveragePercent,
      lhCoveragePct: quality.lhCoveragePercent,
      lipsCoveragePct: quality.lipsCoveragePercent,
      bodyCoveragePct: quality.bodyCoveragePercent,
      startDetected: start != null,
      startTimeStr: startTimeStr,
      endDetected: end != null,
      endTimeStr: endTimeStr,
      durationMs: activityDetector.signDurationMs,
      motionBaseline: activityDetector.baselineMean,
      peakMotion: activityDetector.peakMotion,
      slidingStride: slidingStrideFrames,
      inferenceAttempts: _inferenceAttempts,
      inferenceExecuted: _inferenceExecuted,
      inferenceSkippedBusy: _inferenceSkippedBusy,
      averageInferenceTimeMs: averageInferenceTimeMs,
      candidates: candidates,
      votes: votes,
      stableIds: stableIds,
      stabilityPass: stabilityPass,
      isAccepted: isAccepted,
      acceptedIds: eval?.stableIds ?? const [],
      acceptedGlosses: _acceptedGlosses,
      sequenceConfidence: eval?.sequenceConfidence ?? 0.0,
      reasonCode: eval?.reasonCode ?? 'NO_SIGN_ACTIVITY',
      nanCount: quality.totalNanCount,
      infCount: quality.totalInfCount,
      modelPass: tfliteService.isReady,
      ctcPass: IsharaCtcDecoder.runSelfTests(),
      vocabPass: vocabService.isLoaded,
      pipelinePass: isAccepted && stabilityPass,
    );
  }

  /// نسخ التقرير الرسمي إلى الحافظة
  Future<String> copyReportToClipboard() async {
    final report = generateReportData().toReportText();
    await Clipboard.setData(ClipboardData(text: report));
    return report;
  }
}
