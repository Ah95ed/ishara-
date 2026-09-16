import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ishara/providers/sign_recognition_provider.dart';
import 'package:ishara/services/diagnostics/diagnostic_models.dart';
import 'package:ishara/services/diagnostics/ishara_diagnostic_service.dart';
import 'package:ishara/services/tflite/ishara_recognition_service.dart';
import 'package:provider/provider.dart';

class IsharaDiagnosticView extends StatefulWidget {
  const IsharaDiagnosticView({super.key});

  @override
  State<IsharaDiagnosticView> createState() => _IsharaDiagnosticViewState();
}

class _IsharaDiagnosticViewState extends State<IsharaDiagnosticView>
    with SingleTickerProviderStateMixin {
  final IsharaDiagnosticService _diagService = IsharaDiagnosticService();
  late final TabController _tabController;
  bool _isRunningModelDiagnostic = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _diagService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _diagService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _runModelDiagnostics() async {
    if (_isRunningModelDiagnostic) return;
    setState(() => _isRunningModelDiagnostic = true);

    try {
      final signRecognition = context.read<SignRecognitionProvider>();
      final result = await signRecognition.runModelDiagnostics();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.outputValid
                ? '✅ نجح فحص الموديل المستقل: MODEL EXECUTION = PASS (${result.inferenceTimeMs} ms)'
                : '❌ فشل فحص الموديل: [${result.errorCode}] ${result.errorMessage}',
          ),
          backgroundColor: result.outputValid ? Colors.teal : Colors.redAccent,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ حدث خطأ أثناء تشغيل الفحص: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRunningModelDiagnostic = false);
    }
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
            Text(
              'لوحة التشخيص الشاملة (Diagnostics)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(
              icon: Icon(Icons.memory_rounded),
              text: 'النموذج (MODEL)',
            ),
            Tab(
              icon: Icon(Icons.videocam_rounded),
              text: 'الكاميرا (CAMERA)',
            ),
            Tab(
              icon: Icon(Icons.auto_awesome_motion_rounded),
              text: 'المسار (PIPELINE)',
            ),
          ],
        ),
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildModelSection(),
                  _buildCameraSection(),
                  _buildPipelineSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 1: MODEL SECTION (PATH A)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildModelSection() {
    final tflite = _diagService.tfliteLoad;
    final modelOutput = _diagService.modelOutput;
    final vocab = _diagService.vocabulary;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Action Card to Run Diagnostics on Demand
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.model_training, color: Colors.teal, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'فحص النموذج المستقل (PATH A)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      'اختبار ملف الأصول، Interpreter، Tensors، واستنتاج ببيانات وهمية بمعزل عن الكاميرا',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                icon: _isRunningModelDiagnostic
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow, size: 16),
                label: Text(
                  _isRunningModelDiagnostic ? 'جارٍ الفحص...' : 'فحص الآن',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: _isRunningModelDiagnostic ? null : _runModelDiagnostics,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 1. MODEL FILE
        _buildItemCard(
          title: 'ملف النموذج (MODEL FILE)',
          status: tflite.modelFileStatus,
          errorCode: tflite.errorCode,
          details: [
            'المسار: ${IsharaRecognitionService.modelAssetPath}',
            'حجم الملف بالبايت: ${tflite.modelSizeBytes} بايت',
            'الحجم بالميغابايت: ${tflite.modelSizeMb.toStringAsFixed(2)} MB',
            'حالة الملف: ${tflite.fileFound ? "موجود وسليم بنجاح ✅" : "غير موجود ❌"}',
          ],
        ),

        // 2. INTERPRETER
        _buildItemCard(
          title: 'محرك التشغيل (INTERPRETER)',
          status: tflite.interpreterStatus,
          errorCode: tflite.errorCode,
          failureReason: tflite.exceptionMessage,
          details: [
            'الحالة: ${tflite.interpreterStatus == DiagnosticStageStatus.pass ? "تم الإنشاء بنجاح ✅" : "فشل الإنشاء ❌"}',
            if (tflite.exceptionType != null) 'نوع الاستثناء: ${tflite.exceptionType}',
            if (tflite.exceptionMessage != null) 'رسالة الخطأ: ${tflite.exceptionMessage}',
          ],
        ),

        // 3. INPUT TENSOR
        _buildItemCard(
          title: 'مصفوفة الإدخال (INPUT TENSOR)',
          status: tflite.inputTensorStatus,
          details: [
            'الأبعاد المتوقعة: [1, 128, 86, 2]',
            'الأبعاد الفعلية: ${tflite.inputShape ?? "غير متوفر"}',
            'نوع البيانات المتوقع: FLOAT32 (22,016 قيمة)',
            'نوع البيانات الفعلي: ${tflite.inputType}',
            'التطابق: ${tflite.inputTensorStatus == DiagnosticStageStatus.pass ? "مطابق تماماً ✅" : "غير مطابق ❌"}',
          ],
        ),

        // 4. OUTPUT TENSOR
        _buildItemCard(
          title: 'مصفوفة الإخراج (OUTPUT TENSOR)',
          status: tflite.outputTensorStatus,
          details: [
            'الأبعاد المتوقعة: [1, 29, 684]',
            'الأبعاد الفعلية: ${tflite.outputShape ?? "غير متوفر"}',
            'نوع البيانات المتوقع: FLOAT32',
            'نوع البيانات الفعلي: ${tflite.outputType}',
            'التطابق: ${tflite.outputTensorStatus == DiagnosticStageStatus.pass ? "مطابق تماماً ✅" : "غير مطابق ❌"}',
          ],
        ),

        // 5. STANDALONE INFERENCE
        _buildItemCard(
          title: 'الاستنتاج المستقل (STANDALONE INFERENCE)',
          status: tflite.standaloneInferenceStatus,
          errorCode: tflite.errorCode,
          details: [
            'زمن التنفيذ: ${tflite.standaloneInferenceTimeMs} ms',
            'حالة الاختبار بمدخلات وهمية (22,016 قيمة Float32): ${tflite.standaloneInferenceStatus.displayText}',
          ],
        ),

        // 6. MODEL OUTPUT VALIDATION
        _buildItemCard(
          title: 'التحقق من مخرجات الموديل (MODEL OUTPUT)',
          status: modelOutput.status,
          errorCode: modelOutput.errorCode,
          failureReason: modelOutput.errorMessage,
          details: [
            'فحص القيم غير المعرفة (NaN): ${modelOutput.nanCount}',
            'فحص القيم اللانهائية (Inf): ${modelOutput.infinityCount}',
            'فحص المخرجات الصفرية (All Zeros): ${modelOutput.isAllZeros ? "كلها أصفار ❌" : "سليمة ✅"}',
            'إحصائيات Logits: أدنى=${modelOutput.min.toStringAsFixed(2)}, أقصى=${modelOutput.max.toStringAsFixed(2)}, متوسط=${modelOutput.mean.toStringAsFixed(3)}',
          ],
        ),

        // 7. VOCABULARY
        _buildItemCard(
          title: 'قاموس المفردات (VOCABULARY)',
          status: vocab.status,
          errorCode: vocab.errorCode,
          failureReason: vocab.errorMessage,
          details: [
            'عدد الفئات الإجمالي: ${vocab.totalClasses} (المتوقع 684)',
            'رمز Blank في CTC: المعرف 0 (CTC Blank ID = 0)',
            'المعرفات الصالحة للكلمات: 1 إلى 683',
            'حالة القاموس: ${vocab.isValid ? "صحيح ومكتمل ✅" : "توجد معرفات مفقودة ❌"}',
            'عينة من المفردات:',
            ...vocab.verifiedMappings.take(5).map((m) => '  $m'),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 2: CAMERA & PERSON DETECTION (PATH B)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildCameraSection() {
    final camera = _diagService.camera;
    final person = _diagService.person;
    final hands = _diagService.hands;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 1. CAMERA
        _buildItemCard(
          title: 'الكاميرا (CAMERA)',
          status: camera.status,
          errorCode: camera.errorCode,
          details: [
            'حالة البث: ${camera.isStreaming ? "نشط ويبث الإطارات ✅" : "متوقف ❌"}',
            'معدل الإطارات: ${camera.fps.toStringAsFixed(1)} FPS',
            'عمر الإطار الأخير: ${camera.frameAgeMs} ms',
            'الدقة: ${camera.width}x${camera.height}',
            'الصيغة: ${camera.format}',
            'الدوران: ${camera.rotation}°',
          ],
        ),

        // 2. FRAMES RECEIVED
        _buildItemCard(
          title: 'الإطارات المستلمة (FRAMES RECEIVED)',
          status: camera.framesReceived > 0
              ? DiagnosticStageStatus.pass
              : DiagnosticStageStatus.waiting,
          details: [
            'إجمالي الإطارات المستلمة من الكاميرا: ${camera.framesReceived}',
            'وقت آخر إطار: ${camera.lastFrameTime != null ? "${camera.lastFrameTime!.hour}:${camera.lastFrameTime!.minute}:${camera.lastFrameTime!.second}" : "لم يستلم بعد"}',
          ],
        ),

        // 3. IMAGE CONVERSION
        _buildItemCard(
          title: 'تحويل الصورة للكاشف (IMAGE CONVERSION)',
          status: camera.imageConversionStatus,
          failureReason: camera.imageConversionError,
          details: [
            'طريقة التحويل: دمج مستمر لطبقات YUV420 مع معالجة الـ Strides ومطابقة أبعاد NV21 لـ ML Kit',
            'الحالة: ${camera.imageConversionStatus.displayText}',
            if (camera.imageConversionError != null) 'الخطأ: ${camera.imageConversionError}',
          ],
        ),

        // 4. PERSON DETECTOR CALLS & METRICS
        _buildItemCard(
          title: 'استدعاءات كاشف الشخص (PERSON DETECTOR METRICS)',
          status: camera.personDetectorCalls > 0
              ? (camera.personDetectorErrors == 0
                  ? DiagnosticStageStatus.pass
                  : DiagnosticStageStatus.fail)
              : DiagnosticStageStatus.waiting,
          details: [
            'عدد الاستدعاءات (Calls): ${camera.personDetectorCalls}',
            'عدد النتائج الناجحة (Results): ${camera.personDetectorResults}',
            'عدد الأخطاء (Errors): ${camera.personDetectorErrors}',
          ],
        ),

        // 5. PERSON PRESENCE (Rule: pose || head || face)
        _buildItemCard(
          title: 'حضور الشخص (PERSON PRESENCE)',
          status: person.status,
          errorCode: person.errorCode,
          failureReason: person.failureReason,
          details: [
            'الشخص موجود: ${person.personPresent ? "نعم ✅" : "لا ❌"}',
            'قاعدة التحقق: personPresent = posePresent || headPresent || facePresent',
            'الجسم (Pose): ${person.posePresent ? "مكتشف ✅" : "غير مكتشف ❌"}',
            'الرأس (Head): ${person.headPresent ? "مكتشف ✅" : "غير مكتشف ❌"}',
            'الوجه (Face): ${person.facePresent ? "مكتشف ✅" : "غير مكتشف ❌"}',
          ],
        ),

        // 6. HAND DETECTOR CALLS & METRICS
        _buildItemCard(
          title: 'كاشف الأيدي (HAND DETECTOR METRICS)',
          status: hands.status,
          errorCode: hands.errorCode,
          failureReason: hands.errorMessage,
          details: [
            'استدعاءات كاشف اليد (Calls): ${hands.handDetectorCalls}',
            'النتائج الناجحة (Results): ${hands.handDetectorResults}',
            'الأخطاء والاستثناءات (Errors): ${hands.handDetectorErrors}',
            'كشف اليد اليسرى: [${hands.leftHandLandmarks} / 21 معلماً] (مرات الكشف: ${hands.leftHandResults})',
            'كشف اليد اليمنى: [${hands.rightHandLandmarks} / 21 معلماً] (مرات الكشف: ${hands.rightHandResults})',
            if (hands.exceptionType != null) 'نوع الاستثناء: ${hands.exceptionType}',
            if (hands.stackTraceSnippet != null) 'تتبع الخطأ:\n${hands.stackTraceSnippet}',
          ],
        ),

        // 7. LANDMARK COUNTS (POSE, FACE, HANDS)
        _buildItemCard(
          title: 'معالم الجسم والوجه واليدين (LANDMARKS)',
          status: (camera.poseLandmarks > 0 || camera.faceLandmarks > 0 || hands.leftHandLandmarks > 0 || hands.rightHandLandmarks > 0)
              ? DiagnosticStageStatus.pass
              : DiagnosticStageStatus.waiting,
          details: [
            'معالم وضعية الجسم (Pose): [${camera.poseLandmarks}/25 landmarks] (25 معلماً علوياً)',
            'معالم الوجه/الشفاه (Face/Lips): [${camera.faceLandmarks}/19 landmarks] (19 نقطة شفاه)',
            'اليد اليسرى (Left Hand): [${hands.leftHandLandmarks} / 21 landmarks] (الثقة: ${(hands.leftHandConfidence * 100).toStringAsFixed(1)}%)',
            'اليد اليمنى (Right Hand): [${hands.rightHandLandmarks} / 21 landmarks] (الثقة: ${(hands.rightHandConfidence * 100).toStringAsFixed(1)}%)',
          ],
        ),

        // 8. ROTATION
        _buildItemCard(
          title: 'زوايا الدوران (ROTATIONS)',
          status: DiagnosticStageStatus.pass,
          details: [
            'زاوية معاينة الشاشة (Preview Rotation): ${camera.previewRotation}°',
            'زاوية إدخال الكاشف (Detector Input Rotation): ${camera.detectorInputRotation}°',
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 3: SIGN PIPELINE (KEYPOINTS -> BUFFER -> CTC)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPipelineSection() {
    final keypoints = _diagService.keypoints;
    final groups = _diagService.pointGroups;
    final preprocess = _diagService.preprocessing;
    final buffer = _diagService.buffer;
    final input = _diagService.modelInput;
    final inference = _diagService.inference;
    final ctc = _diagService.ctc;
    final finalOut = _diagService.finalOutput;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 1. KEYPOINTS (86 EXACT)
        _buildItemCard(
          title: 'الـ 86 نقطة بالضبط (86 KEYPOINTS)',
          status: keypoints.status,
          errorCode: keypoints.errorCode,
          failureReason: keypoints.errorMessage,
          details: [
            'عدد النقاط الإجمالي: [${keypoints.validKeypoints} / 86]',
            'المفقود: ${keypoints.missingKeypoints}',
            'الأيدي [0..41]: ${groups.totalHandValid} / 42 (يمنى: ${groups.rightHandValid}/21، يسرى: ${groups.leftHandValid}/21)',
            'الشفاه [42..60]: ${groups.faceLipValid} / 19',
            'الجسم العلوي [61..85]: ${groups.bodyValid} / 25',
            'عينة P0 (معصم أيمن): ${keypoints.sampleP0}',
            'عينة P1: ${keypoints.sampleP1}',
            'عينة P2: ${keypoints.sampleP2}',
          ],
        ),

        // 2. PREPROCESSING
        _buildItemCard(
          title: 'المعالجة المسبقة والتطبيع (PREPROCESSING)',
          status: preprocess.status,
          errorCode: preprocess.errorCode,
          failureReason: preprocess.errorMessage,
          details: [
            'المدخلات الخام: X=[${preprocess.rawMinX.toStringAsFixed(2)} .. ${preprocess.rawMaxX.toStringAsFixed(2)}], Y=[${preprocess.rawMinY.toStringAsFixed(2)} .. ${preprocess.rawMaxY.toStringAsFixed(2)}]',
            'بعد التطبيع الصارم: أدنى=${preprocess.normMin.toStringAsFixed(2)}, أقصى=${preprocess.normMax.toStringAsFixed(2)}, متوسط=${preprocess.normMean.toStringAsFixed(3)}',
            'فحص NaN: ${preprocess.hasNan ? "يوجد NaN ❌" : "سليم ✅"}',
          ],
        ),

        // 3. BUFFER
        _buildItemCard(
          title: 'المخزن الزمني (TEMPORAL BUFFER)',
          status: buffer.status,
          errorCode: buffer.errorCode,
          failureReason: buffer.errorMessage,
          details: [
            'امتلاء المخزن: [${buffer.currentFrames} / 128]',
            'إطارات شخص صالحة: ${buffer.personFrames}',
            'إطارات أيدي صالحة: ${buffer.handFrames}',
            'إطارات رأس صالحة: ${buffer.headFrames}',
          ],
        ),

        // 4. REAL MODEL INPUT
        _buildItemCard(
          title: 'مدخلات النموذج الحقيقي (REAL INPUT)',
          status: input.status,
          errorCode: input.errorCode,
          failureReason: input.errorMessage,
          details: [
            'الشكل: ${input.shape} (المتوقع [1, 128, 86, 2])',
            'إجمالي القيم: ${input.totalValues} (المتوقع 22016)',
            'نسبة الأصفار: ${input.zeroPercentage.toStringAsFixed(1)}%',
            'إحصائيات: أدنى=${input.min.toStringAsFixed(2)}, أقصى=${input.max.toStringAsFixed(2)}',
          ],
        ),

        // 5. REAL INFERENCE
        _buildItemCard(
          title: 'استنتاج النموذج الحقيقي (REAL INFERENCE)',
          status: inference.status,
          errorCode: inference.errorCode,
          failureReason: inference.exceptionMessage,
          details: [
            'زمن الاستنتاج: ${inference.inferenceTimeMs} ms',
            if (inference.exceptionType != null) 'الاستثناء: ${inference.exceptionType}: ${inference.exceptionMessage}',
          ],
        ),

        // 6. CTC DECODER
        _buildItemCard(
          title: 'مفكك تشفير CTC (CTC DECODER)',
          status: ctc.status,
          errorCode: ctc.errorCode,
          failureReason: ctc.errorMessage,
          details: [
            'المعرفات الخام: ${ctc.rawIds.take(15).toList()}${ctc.rawIds.length > 15 ? "..." : ""}',
            'بعد دمج التكرارات: ${ctc.collapsedIds}',
            'بعد إزالة الـ Blank: ${ctc.afterBlankRemovalIds}',
            'الكلمات المفككة: ${ctc.decodedGlosses}',
            'متوسط الثقة: ${(ctc.averageConfidence * 100).toStringAsFixed(1)}%',
          ],
        ),

        // 7. FINAL GLOSS & DECISION
        _buildItemCard(
          title: 'النتيجة النهائية (FINAL GLOSS)',
          status: finalOut.status,
          details: [
            'المخرج الأولي للنموذج: "${finalOut.rawModelGloss ?? "—"}"',
            'القرار: ${finalOut.decision}',
            'الكلمة المعتمدة: "${finalOut.finalGloss ?? "NONE"}"',
            if (finalOut.rejectionReason != null) 'سبب الرفض: ${finalOut.rejectionReason}',
          ],
        ),

        const SizedBox(height: 12),
        _buildEventsHistorySection(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REUSABLE ITEM CARD
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildItemCard({
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
        initiallyExpanded: status == DiagnosticStageStatus.fail ||
            status == DiagnosticStageStatus.waiting,
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
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
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
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT HISTORY
  // ═══════════════════════════════════════════════════════════════════════════
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
            Text(
              'سجل الأحداث الأخيرة (${events.length} حدث)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        children: [
          Container(
            height: 250,
            padding: const EdgeInsets.all(8),
            color: Colors.black12,
            child: events.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد أحداث مسجلة بعد',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
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
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
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
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
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
