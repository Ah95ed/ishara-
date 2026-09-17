/// BodyPartsDetectionState
/// نموذج بيانات بسيط وموحد يمثل حالة اكتشاف الأجزاء الـ 6 في إطار الكاميرا.
class BodyPartsDetectionState {
  final bool person;
  final bool head;
  final bool face;
  final bool lips;
  final bool leftHand;
  final bool rightHand;

  final int leftHandLandmarks;
  final int rightHandLandmarks;
  final int faceLandmarksCount;
  final int poseLandmarksCount;
  final double fps;

  const BodyPartsDetectionState({
    this.person = false,
    this.head = false,
    this.face = false,
    this.lips = false,
    this.leftHand = false,
    this.rightHand = false,
    this.leftHandLandmarks = 0,
    this.rightHandLandmarks = 0,
    this.faceLandmarksCount = 0,
    this.poseLandmarksCount = 0,
    this.fps = 0.0,
  });

  static const BodyPartsDetectionState empty = BodyPartsDetectionState();

  BodyPartsDetectionState copyWith({
    bool? person,
    bool? head,
    bool? face,
    bool? lips,
    bool? leftHand,
    bool? rightHand,
    int? leftHandLandmarks,
    int? rightHandLandmarks,
    int? faceLandmarksCount,
    int? poseLandmarksCount,
    double? fps,
  }) {
    return BodyPartsDetectionState(
      person: person ?? this.person,
      head: head ?? this.head,
      face: face ?? this.face,
      lips: lips ?? this.lips,
      leftHand: leftHand ?? this.leftHand,
      rightHand: rightHand ?? this.rightHand,
      leftHandLandmarks: leftHandLandmarks ?? this.leftHandLandmarks,
      rightHandLandmarks: rightHandLandmarks ?? this.rightHandLandmarks,
      faceLandmarksCount: faceLandmarksCount ?? this.faceLandmarksCount,
      poseLandmarksCount: poseLandmarksCount ?? this.poseLandmarksCount,
      fps: fps ?? this.fps,
    );
  }

  @override
  String toString() {
    return 'BodyPartsDetectionState(person: $person, head: $head, face: $face, lips: $lips, leftHand: $leftHand ($leftHandLandmarks), rightHand: $rightHand ($rightHandLandmarks), fps: ${fps.toStringAsFixed(1)})';
  }
}
