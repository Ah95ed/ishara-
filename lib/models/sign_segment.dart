/// كيان مقطع الإشارة الزمني المكتمل (SignSegment)
///
/// المتطلب 26: لا يُعرض أي Gloss قبل إغلاق واكتمال SignSegment.
class SignSegment {
  final int startFrame;
  final int endFrame;
  final int durationFrames;
  final List<List<List<double>>> frames;
  final double validHandRatio;
  final double validHeadRatio;
  final double validFaceRatio;
  final double averageMotionEnergy;
  final String? candidate;
  final double confidence;
  final double stability;
  final DateTime createdAt;

  SignSegment({
    required this.startFrame,
    required this.endFrame,
    required this.durationFrames,
    required this.frames,
    required this.validHandRatio,
    required this.validHeadRatio,
    this.validFaceRatio = 1.0,
    required this.averageMotionEnergy,
    this.candidate,
    this.confidence = 0.0,
    this.stability = 0.0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  SignSegment copyWith({
    String? candidate,
    double? confidence,
    double? stability,
  }) {
    return SignSegment(
      startFrame: startFrame,
      endFrame: endFrame,
      durationFrames: durationFrames,
      frames: frames,
      validHandRatio: validHandRatio,
      validHeadRatio: validHeadRatio,
      validFaceRatio: validFaceRatio,
      averageMotionEnergy: averageMotionEnergy,
      candidate: candidate ?? this.candidate,
      confidence: confidence ?? this.confidence,
      stability: stability ?? this.stability,
      createdAt: createdAt,
    );
  }
}
