import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ishara/services/diagnostics/diagnostic_models.dart';
import 'package:ishara/services/diagnostics/ishara_diagnostic_service.dart';

class IsharaDiagnosticView extends StatefulWidget {
  const IsharaDiagnosticView({super.key});

  @override
  State<IsharaDiagnosticView> createState() => _IsharaDiagnosticViewState();
}

class _IsharaDiagnosticViewState extends State<IsharaDiagnosticView> {
  final IsharaDiagnosticService _diagService = IsharaDiagnosticService();

  @override
  void initState() {
    super.initState();
    _diagService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _diagService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _copySnapshot() {
    final snapshot = _diagService.takeSnapshot();
    final text = snapshot.toFormattedText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تم نسخ تقرير التشخيص بالكامل إلى الحافظة (Snapshot Copied)'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.teal,
      ),
    );
  }

  void _showJsonModal() {
    final snapshot = _diagService.takeSnapshot();
    final json = snapshot.toJsonString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.data_object, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('JSON Snapshot Data'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('نسخ JSON'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ الـ JSON')),
              );
            },
          ),
          TextButton(
            child: const Text('إغلاق'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFrozen = _diagService.isFrozen;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.biotech_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Text('تشخيص الـ Pipeline (Diagnostic Mode)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isFrozen ? 'إلغاء التجميد (Unfreeze)' : 'تجميد اللقطة (Freeze)',
            icon: Icon(
              isFrozen ? Icons.play_arrow_rounded : Icons.pause_circle_filled,
              color: isFrozen ? Colors.greenAccent : Colors.amber,
              size: 28,
            ),
            onPressed: () => _diagService.toggleFreeze(),
          ),
          IconButton(
            tooltip: 'نسخ التقرير الشامل (Copy Snapshot)',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: _copySnapshot,
          ),
          IconButton(
            tooltip: 'عرض JSON',
            icon: const Icon(Icons.code_rounded),
            onPressed: _showJsonModal,
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            if (isFrozen)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                color: Colors.amber.withValues(alpha: 0.2),
                child: const Row(
                  children: [
                    Icon(Icons.pause, size: 16, color: Colors.amber),
                    SizedBox(width: 8),
                    Text(
                      'تم تجميد الشاشة للمعاينة (FROZEN SNAPSHOT) — البيانات ثابتة الآن',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildControlHeader(),
                  const SizedBox(height: 12),
                  _buildStageCard(
                    stageNumber: 1,
                    title: 'الكاميرا (CAMERA)',
                    status: _diagService.camera.status,
                    errorCode: _diagService.camera.errorCode,
                    details: [
                      'الحالة: ${_diagService.camera.isStreaming ? "بث نشط" : "متوقف"}',
                      'معدل الإطارات: ${_diagService.camera.fps.toStringAsFixed(1)} FPS',
                      'عمر الفريم: ${_diagService.camera.frameAgeMs} ms',
                      'الأبعاد: ${_diagService.camera.width}x${_diagService.camera.height}',
                      'التنسيق: ${_diagService.camera.format}',
                      'الدوران: ${_diagService.camera.rotation}°',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 2,
                    title: 'كشف وجود الشخص (PERSON DETECTION)',
                    status: _diagService.person.status,
                    errorCode: _diagService.person.errorCode,
                    failureReason: _diagService.person.failureReason,
                    details: [
                      'وجود الشخص: ${_diagService.person.personPresent ? "نعم ✅" : "لا ❌"}',
                      'وضعية الجسم (Pose): ${_diagService.person.posePresent ? "موجود ✅" : "غير موجود ❌"}',
                      'الرأس (Head): ${_diagService.person.headPresent ? "موجود ✅" : "غير موجود ❌"}',
                      'الوجه (Face): ${_diagService.person.facePresent ? "موجود ✅" : "غير موجود ❌"}',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 3,
                    title: 'كشف الأيدي (HAND DETECTION)',
                    status: _diagService.hands.status,
                    errorCode: _diagService.hands.errorCode,
                    failureReason: _diagService.hands.errorMessage,
                    details: [
                      'اليد اليسرى: ${_diagService.hands.leftHandDetected ? "مكتشفة (${_diagService.hands.leftHandLandmarks} نقطة) - ثقة: ${(_diagService.hands.leftHandConfidence * 100).toStringAsFixed(1)}%" : "غير مكتشفة (0 نقاط)"}',
                      'اليد اليمنى: ${_diagService.hands.rightHandDetected ? "مكتشفة (${_diagService.hands.rightHandLandmarks} نقطة) - ثقة: ${(_diagService.hands.rightHandConfidence * 100).toStringAsFixed(1)}%" : "غير مكتشفة (0 نقاط)"}',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 4,
                    title: 'معالم الوجه والرأس والشفاه (FACE / HEAD / LIPS)',
                    status: _diagService.faceHead.status,
                    details: [
                      'الرأس: ${_diagService.faceHead.headDetected ? "نعم (${_diagService.faceHead.validHeadPoints}/25 نقطة)" : "لا"}',
                      'الوجه: ${_diagService.faceHead.faceDetected ? "نعم" : "لا"}',
                      'الشفاه: ${_diagService.faceHead.lipsDetected ? "نعم (${_diagService.faceHead.validLipPoints}/19 نقطة)" : "لا (مستقلة عن الشخص)"}',
                      'درجة الثقة: ${(_diagService.faceHead.confidence * 100).toStringAsFixed(1)}%',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 5,
                    title: 'فحص الـ 86 نقطة بالضبط (EXACT 86 KEYPOINTS)',
                    status: _diagService.keypoints.status,
                    errorCode: _diagService.keypoints.errorCode,
                    failureReason: _diagService.keypoints.errorMessage,
                    details: [
                      'عدد النقاط الإجمالي: ${_diagService.keypoints.keypointCount} / 86',
                      'النقاط الصالحة: ${_diagService.keypoints.validKeypoints}',
                      'النقاط المفقودة: ${_diagService.keypoints.missingKeypoints}',
                      'القيم غير المعرفة (NaN): ${_diagService.keypoints.nanCount}',
                      'القيم اللانهائية (Inf): ${_diagService.keypoints.infinityCount}',
                      'النقاط الصفرية: ${_diagService.keypoints.zeroCount}',
                      'عينة P0 (معصم أيمن): ${_diagService.keypoints.sampleP0}',
                      'عينة P1: ${_diagService.keypoints.sampleP1}',
                      'عينة P2: ${_diagService.keypoints.sampleP2}',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 6,
                    title: 'فئات النقاط حسب التدريب (POINT GROUPS)',
                    status: _diagService.pointGroups.status,
                    errorCode: _diagService.pointGroups.errorCode,
                    failureReason: _diagService.pointGroups.errorMessage,
                    details: [
                      'نقاط الأيدي الإجمالية: ${_diagService.pointGroups.totalHandValid} / 42',
                      '  - يد يمنى [0..20]: ${_diagService.pointGroups.rightHandValid} / 21',
                      '  - يد يسرى [21..41]: ${_diagService.pointGroups.leftHandValid} / 21',
                      'نقاط الشفاه [42..60]: ${_diagService.pointGroups.faceLipValid} / 19',
                      'نقاط الجسم العلوي [61..85]: ${_diagService.pointGroups.bodyValid} / 25',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 7,
                    title: 'المعالجة المسبقة والتطبيع (PREPROCESSING)',
                    status: _diagService.preprocessing.status,
                    errorCode: _diagService.preprocessing.errorCode,
                    failureReason: _diagService.preprocessing.errorMessage,
                    details: [
                      'المدخلات الخام: X=[${_diagService.preprocessing.rawMinX.toStringAsFixed(2)} .. ${_diagService.preprocessing.rawMaxX.toStringAsFixed(2)}], Y=[${_diagService.preprocessing.rawMinY.toStringAsFixed(2)} .. ${_diagService.preprocessing.rawMaxY.toStringAsFixed(2)}]',
                      'بعد التطبيع (datasetv2.py): أدنى=${_diagService.preprocessing.normMin.toStringAsFixed(2)}, أقصى=${_diagService.preprocessing.normMax.toStringAsFixed(2)}, متوسط=${_diagService.preprocessing.normMean.toStringAsFixed(3)}',
                      'فحص NaN: ${_diagService.preprocessing.hasNan ? "يوجد NaN ❌" : "سليم ✅"}',
                      'فحص القيم المتطرفة: ${_diagService.preprocessing.hasExtremeValues ? "توجد قيم شاذة ❌" : "ضمن النطاق ✅"}',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 8,
                    title: 'المخزن الزمني للإطارات (TEMPORAL BUFFER)',
                    status: _diagService.buffer.status,
                    errorCode: _diagService.buffer.errorCode,
                    failureReason: _diagService.buffer.errorMessage,
                    details: [
                      'امتلاء المخزن: ${_diagService.buffer.currentFrames} / ${_diagService.buffer.requiredFrames}',
                      'إطارات شخص صالحة: ${_diagService.buffer.personFrames}',
                      'إطارات أيدي صالحة: ${_diagService.buffer.handFrames}',
                      'إطارات رأس صالحة: ${_diagService.buffer.headFrames}',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 9,
                    title: 'مصفوفة إدخال النموذج (EXACT MODEL INPUT)',
                    status: _diagService.modelInput.status,
                    errorCode: _diagService.modelInput.errorCode,
                    failureReason: _diagService.modelInput.errorMessage,
                    details: [
                      'أبعاد المصفوفة: ${_diagService.modelInput.shape}',
                      'نوع البيانات: ${_diagService.modelInput.dtype}',
                      'عدد القيم الإجمالي: ${_diagService.modelInput.totalValues} (المتوقع 22016)',
                      'إحصائيات الإدخال: أدنى=${_diagService.modelInput.min.toStringAsFixed(2)}, أقصى=${_diagService.modelInput.max.toStringAsFixed(2)}, متوسط=${_diagService.modelInput.mean.toStringAsFixed(3)}',
                      'نسبة الأصفار: ${_diagService.modelInput.zeroPercentage.toStringAsFixed(1)}%',
                      'عدد NaN: ${_diagService.modelInput.nanCount}',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 10,
                    title: 'تحميل نموذج TFLite (TFLITE LOADING)',
                    status: _diagService.tfliteLoad.status,
                    errorCode: _diagService.tfliteLoad.errorCode,
                    failureReason: _diagService.tfliteLoad.errorMessage,
                    details: [
                      'ملف ishara_model.tflite: ${_diagService.tfliteLoad.fileFound ? "موجود ✅" : "مفقود ❌"}',
                      'حالة التحميل: ${_diagService.tfliteLoad.isLoaded ? "جاهز ومُحمّل ✅" : "غير جاهز"}',
                      'شكل الدخل المتوقع: [1, 128, 86, 2] | الفعلي: ${_diagService.tfliteLoad.inputShape}',
                      'شكل الخرج المتوقع: [1, 29, 684] | الفعلي: ${_diagService.tfliteLoad.outputShape}',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 11,
                    title: 'تشغيل الاستنتاج (TFLITE INFERENCE)',
                    status: _diagService.inference.status,
                    errorCode: _diagService.inference.errorCode,
                    failureReason: _diagService.inference.exceptionMessage,
                    details: [
                      'زمن الاستنتاج: ${_diagService.inference.inferenceTimeMs} ms',
                      if (_diagService.inference.exceptionType != null)
                        'نوع الاستثناء: ${_diagService.inference.exceptionType}',
                      if (_diagService.inference.stackTraceSnippet != null)
                        'تتبع الخطأ: ${_diagService.inference.stackTraceSnippet}',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 12,
                    title: 'التحقق من مخرجات النموذج (MODEL OUTPUT VALIDATION)',
                    status: _diagService.modelOutput.status,
                    errorCode: _diagService.modelOutput.errorCode,
                    failureReason: _diagService.modelOutput.errorMessage,
                    details: [
                      'أبعاد المخرجات: ${_diagService.modelOutput.outputShape}',
                      'فحص NaN: ${_diagService.modelOutput.nanCount}',
                      'فحص Inf: ${_diagService.modelOutput.infinityCount}',
                      'مخرجات صفرية بالكامل: ${_diagService.modelOutput.isAllZeros ? "نعم ❌" : "لا ✅"}',
                      'إحصائيات الـ Logits: أدنى=${_diagService.modelOutput.min.toStringAsFixed(2)}, أقصى=${_diagService.modelOutput.max.toStringAsFixed(2)}',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 13,
                    title: 'أعلى الفئات الخام (RAW TOP CLASSES)',
                    status: _diagService.rawTopClasses.status,
                    details: [
                      'نسبة Blank الإجمالية: ${_diagService.rawTopClasses.blankRatio}',
                      'هل Blank مسيطر: ${_diagService.rawTopClasses.isBlankDominant ? "نعم (حركة غير إشارية)" : "لا"}',
                      ..._diagService.rawTopClasses.top5.map(
                        (c) => '#${c.rank}: معرف ${c.classId} -> "${c.gloss}" (${c.score})',
                      ),
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 14,
                    title: 'مفكك تشفير CTC (CTC DECODER)',
                    status: _diagService.ctc.status,
                    errorCode: _diagService.ctc.errorCode,
                    failureReason: _diagService.ctc.errorMessage,
                    details: [
                      'المعرفات الخام (RAW IDS): ${_diagService.ctc.rawIds.take(15).toList()}${_diagService.ctc.rawIds.length > 15 ? "..." : ""}',
                      'بعد دمج التكرارات (COLLAPSED): ${_diagService.ctc.collapsedIds}',
                      'بعد إزالة الـ Blank (CLEAN): ${_diagService.ctc.afterBlankRemovalIds}',
                      'الكلمات المستخرجة: ${_diagService.ctc.decodedGlosses}',
                      'متوسط الثقة: ${(_diagService.ctc.averageConfidence * 100).toStringAsFixed(1)}%',
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 15,
                    title: 'قاموس المفردات (VOCABULARY MAPPING)',
                    status: _diagService.vocabulary.status,
                    errorCode: _diagService.vocabulary.errorCode,
                    failureReason: _diagService.vocabulary.errorMessage,
                    details: [
                      'إجمالي الكلمات: ${_diagService.vocabulary.totalClasses} (المتوقع 684)',
                      'عينة من القاموس:',
                      ..._diagService.vocabulary.verifiedMappings.take(5).map((m) => '  $m'),
                    ],
                  ),
                  _buildStageCard(
                    stageNumber: 16,
                    title: 'النتيجة النهائية والقبول (FINAL OUTPUT & DECISION)',
                    status: _diagService.finalOutput.status,
                    details: [
                      'نتيجة الموديل الخام (RAW): "${_diagService.finalOutput.rawModelGloss ?? "—"}"',
                      'القرار النهائي (DECISION): ${_diagService.finalOutput.decision}',
                      'الكلمة المعتمدة (CONFIRMED): "${_diagService.finalOutput.finalGloss ?? "—"}"',
                      if (_diagService.finalOutput.rejectionReason != null)
                        'سبب الرفض: ${_diagService.finalOutput.rejectionReason}',
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildEventsHistorySection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _diagService.isFrozen ? Colors.amber : Colors.greenAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _diagService.isFrozen ? 'الحالة: مجمدة للفحص' : 'الحالة: تشخيص حي ومباشر',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.camera_alt_outlined, size: 16),
                label: const Text('لقطة فورية للتقرير', style: TextStyle(fontSize: 12)),
                onPressed: _copySnapshot,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStageCard({
    required int stageNumber,
    required String title,
    required DiagnosticStageStatus status,
    String? errorCode,
    String? failureReason,
    required List<String> details,
  }) {
    final Color color;
    switch (status) {
      case DiagnosticStageStatus.pass:
        color = Colors.greenAccent;
        break;
      case DiagnosticStageStatus.fail:
        color = Colors.redAccent;
        break;
      case DiagnosticStageStatus.waiting:
        color = Colors.amber;
        break;
      case DiagnosticStageStatus.running:
        color = Colors.lightBlueAccent;
        break;
      case DiagnosticStageStatus.skipped:
        color = Colors.grey;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: ExpansionTile(
        initiallyExpanded: status == DiagnosticStageStatus.fail || status == DiagnosticStageStatus.waiting,
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            '$stageNumber',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            status.displayText,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.black12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (errorCode != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'رمز الخطأ: $errorCode',
                          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                        ),
                        if (failureReason != null)
                          Text(
                            'السبب: $failureReason',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                ...details.map(
                  (d) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      d,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsHistorySection() {
    final events = _diagService.eventHistory.toList().reversed.toList();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        title: Row(
          children: [
            const Icon(Icons.history, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Text('سجل الأحداث الـ 50 الأخيرة (${events.length} حدث)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        children: [
          Container(
            height: 250,
            padding: const EdgeInsets.all(8),
            color: Colors.black12,
            child: events.isEmpty
                ? const Center(child: Text('لا توجد أحداث مسجلة بعد', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (ctx, idx) {
                      final e = events[idx];
                      Color color = Colors.grey;
                      if (e.status == DiagnosticStageStatus.pass) color = Colors.greenAccent;
                      if (e.status == DiagnosticStageStatus.fail) color = Colors.redAccent;
                      if (e.status == DiagnosticStageStatus.waiting) color = Colors.amber;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.timeFormatted,
                              style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                e.stage,
                                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(e.status.icon, style: const TextStyle(fontSize: 11)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${e.errorCode != null ? "[${e.errorCode}] " : ""}${e.message}',
                                style: const TextStyle(fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
