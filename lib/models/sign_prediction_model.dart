import 'package:ishara/models/landmarks_model.dart';

class SignPrediction {
  final String label;
  final double confidence;
  final DateTime timestamp;
  final Handedness? handedness;
  final int? signId;

  const SignPrediction({
    required this.label,
    required this.confidence,
    required this.timestamp,
    this.handedness,
    this.signId,
  });

  SignPrediction copyWith({
    String? label,
    double? confidence,
    DateTime? timestamp,
    Handedness? handedness,
    int? signId,
  }) {
    return SignPrediction(
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      timestamp: timestamp ?? this.timestamp,
      handedness: handedness ?? this.handedness,
      signId: signId ?? this.signId,
    );
  }
}
