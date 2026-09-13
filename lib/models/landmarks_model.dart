class HandLandmark {
  final int index;
  final double x;
  final double y;
  final double z;

  const HandLandmark({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
  });

  factory HandLandmark.fromList(List<double> values, int startIndex) {
    return HandLandmark(
      index: startIndex ~/ 3,
      x: values[startIndex],
      y: values[startIndex + 1],
      z: values[startIndex + 2],
    );
  }

  List<double> toList() => [x, y, z];
}

enum HandPresenceState {
  noHand,
  candidateHand,
  confirmedHumanHand,
}

enum HandRejectionReason {
  none,
  noHand,
  lowConfidence,
  staleFrame,
  invalidGeometry,
  detectorDisagreement,
}

extension HandRejectionReasonExt on HandRejectionReason {
  String get code {
    switch (this) {
      case HandRejectionReason.none:
        return 'NONE';
      case HandRejectionReason.noHand:
        return 'NO_HAND';
      case HandRejectionReason.lowConfidence:
        return 'LOW_CONFIDENCE';
      case HandRejectionReason.staleFrame:
        return 'STALE_FRAME';
      case HandRejectionReason.invalidGeometry:
        return 'INVALID_GEOMETRY';
      case HandRejectionReason.detectorDisagreement:
        return 'DETECTOR_DISAGREEMENT';
    }
  }
}

enum Handedness { left, right, unknown }

class HandLandmarks {
  final List<HandLandmark> landmarks;
  final Handedness handedness;
  final double handDetectorConfidence;
  final double mediaPipePresenceConfidence;
  final double trackingConfidence;
  final double confidence;
  final int frameId;
  final int detectedHandsCount;

  const HandLandmarks({
    required this.landmarks,
    required this.handedness,
    this.handDetectorConfidence = 0.85,
    this.mediaPipePresenceConfidence = 0.85,
    this.trackingConfidence = 0.85,
    required this.confidence,
    this.frameId = 0,
    this.detectedHandsCount = 1,
  });

  bool get isValid => landmarks.length == 21 && confidence > 0;
}
