/// حالات اختبار إشارات تطبيق Ishara المنظمة بدقة وفق نموذج الحالة (State Machine)
enum IsharaTestState {
  idle,         // في انتظار بدء الاختبار الأول
  countdown,    // العد التنازلي قبل بدء التسجيل (3.. 2.. 1)
  recordingA,   // جارٍ تسجيل 128 إطاراً للحركة الأولى (Frames: 0..128 / 128)
  processingA,  // جارٍ تشغيل استنتاج الموديل للحركة الأولى
  readyForB,    // اكتمل Test A وبانتظار بدء Test B
  recordingB,   // جارٍ تسجيل 128 إطاراً للحركة الثانية (Frames: 0..128 / 128)
  processingB,  // جارٍ تشغيل استنتاج الموديل للحركة الثانية ومقارنة A و B
  completed,    // اكتمل الاختباران وتم توليد التقرير وجاهز للنسخ
}

extension IsharaTestStateExt on IsharaTestState {
  /// هل يتم حالياً تسجيل الإطارات للحركة A أو B؟
  bool get isRecording =>
      this == IsharaTestState.recordingA || this == IsharaTestState.recordingB;

  /// هل يتم حالياً تشغيل الموديل في الخلفية؟
  bool get isProcessing =>
      this == IsharaTestState.processingA || this == IsharaTestState.processingB;

  /// هل يتم حالياً تشغيل العد التنازلي؟
  bool get isCountdown => this == IsharaTestState.countdown;

  /// هل اكتمل الاختباران معاً؟
  bool get isCompleted => this == IsharaTestState.completed;

  /// هل تم إنجاز Test A بنجاح؟
  bool get isTestADone =>
      this == IsharaTestState.readyForB ||
      this == IsharaTestState.recordingB ||
      this == IsharaTestState.processingB ||
      this == IsharaTestState.completed;

  /// هل تم إنجاز Test B بنجاح؟
  bool get isTestBDone => this == IsharaTestState.completed;
}
