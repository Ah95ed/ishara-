import 'package:ishara/models/landmarks_model.dart';

class SignPrediction {
  final String label;
  final double confidence;
  final DateTime timestamp;
  final Handedness? handedness;
  final int? signId;

  // ── حقول طبقة الرفض ودقة القرار (Rejection & Decision Margin) ──
  final String? secondLabel;
  final double secondConfidence;
  final double confidenceMargin;
  final bool isRejected;
  final String? rejectionReason;

  const SignPrediction({
    required this.label,
    required this.confidence,
    required this.timestamp,
    this.handedness,
    this.signId,
    this.secondLabel,
    this.secondConfidence = 0.0,
    double? confidenceMargin,
    this.isRejected = false,
    this.rejectionReason,
  }) : confidenceMargin = confidenceMargin ?? (confidence - secondConfidence > 0 ? confidence - secondConfidence : 0.0);

  SignPrediction copyWith({
    String? label,
    double? confidence,
    DateTime? timestamp,
    Handedness? handedness,
    int? signId,
    String? secondLabel,
    double? secondConfidence,
    double? confidenceMargin,
    bool? isRejected,
    String? rejectionReason,
  }) {
    return SignPrediction(
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      timestamp: timestamp ?? this.timestamp,
      handedness: handedness ?? this.handedness,
      signId: signId ?? this.signId,
      secondLabel: secondLabel ?? this.secondLabel,
      secondConfidence: secondConfidence ?? this.secondConfidence,
      confidenceMargin: confidenceMargin ?? this.confidenceMargin,
      isRejected: isRejected ?? this.isRejected,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }

  @override
  String toString() {
    return 'SignPrediction($label, conf: ${confidence.toStringAsFixed(2)}, top2: $secondLabel (${secondConfidence.toStringAsFixed(2)}), margin: ${confidenceMargin.toStringAsFixed(2)})';
  }
}
