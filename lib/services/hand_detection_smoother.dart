import 'package:ishara/models/landmarks_model.dart';
import 'package:ishara/services/hand_geometry_validator.dart';

/// نظام التحقق الثنائي وإدارة حالات اليد
///
/// HARD RULE: عند أي Frame نتيجتها No Hand → مسح فوري لجميع المعالم
/// لا يوجد holdDuration ولا cached landmarks ولا lastResult يُعاد استخدامه
class HandDetectionSmoother {
  final double minConfidenceThreshold;
  final int consecutiveConfirmationFrames;

  HandLandmarks? _rawDetection;
  HandLandmarks? _confirmedDetection;

  HandPresenceState _presenceState = HandPresenceState.noHand;
  int _consecutiveValidCount = 0;

  int _currentFrameId = 0;
  int _resultFrameId = 0;
  bool _isStaleResult = false;
  bool _geometryValid = false;
  HandRejectionReason _rejectionReason = HandRejectionReason.noHand;

  HandDetectionSmoother({
    this.minConfidenceThreshold = 0.85,
    this.consecutiveConfirmationFrames = 3,
  });

  HandLandmarks? get rawDetection => _rawDetection;
  HandLandmarks? get stableDetection => isRealHand ? _confirmedDetection : null;
  HandLandmarks? get confirmedLandmarks => isRealHand ? _confirmedDetection : null;

  HandPresenceState get presenceState => _presenceState;
  bool get isRealHand => _presenceState == HandPresenceState.confirmedHumanHand;
  bool get isConfirmedHumanHand => isRealHand;
  bool get hasStableHand => isRealHand;

  bool get rawHandDetected => _rawDetection != null && _rawDetection!.isValid;
  double get handDetectorConfidence => _rawDetection?.handDetectorConfidence ?? 0.0;
  double get mediaPipePresenceConfidence => _rawDetection?.mediaPipePresenceConfidence ?? 0.0;
  double get trackingConfidence => _rawDetection?.trackingConfidence ?? 0.0;

  int get frameId => _currentFrameId;
  int get resultFrameId => _resultFrameId;
  bool get isStaleResult => _isStaleResult;
  bool get geometryValid => _geometryValid;

  HandRejectionReason get rejectionReasonEnum => _rejectionReason;
  String get rejectionReason => _rejectionReason.code;

  int get consecutiveValidFrames => _consecutiveValidCount;

  bool processRawDetection(HandLandmarks? raw, int currentFrameId) {
    _currentFrameId = currentFrameId;
    _rawDetection = raw;
    final previousState = _presenceState;

    // RULE: No Hand → IMMEDIATE FAST CLEAR — لا أي استثناء ولا holdDuration
    if (raw == null || !raw.isValid) {
      _immediateClear(HandRejectionReason.noHand);
      return _presenceState != previousState;
    }

    _resultFrameId = raw.frameId;

    // Stale Frame Check — إذا رجعت نتيجة متأخرة تجاهلها فوراً
    if (_resultFrameId > 0 && (_currentFrameId - _resultFrameId).abs() > 1) {
      _isStaleResult = true;
      _immediateClear(HandRejectionReason.staleFrame);
      return _presenceState != previousState;
    }
    _isStaleResult = false;

    // Confidence Gate: الكاشف المستقل يجب أن يكون فوق الحد الأدنى
    if (raw.handDetectorConfidence < minConfidenceThreshold) {
      _immediateClear(HandRejectionReason.detectorDisagreement);
      return _presenceState != previousState;
    }

    if (raw.mediaPipePresenceConfidence < minConfidenceThreshold ||
        raw.trackingConfidence < minConfidenceThreshold) {
      _immediateClear(HandRejectionReason.lowConfidence);
      return _presenceState != previousState;
    }

    // Geometry Validation
    final geoResult = HandGeometryValidator.validate(raw);
    _geometryValid = geoResult.isValid;

    if (!_geometryValid) {
      _immediateClear(HandRejectionReason.invalidGeometry);
      return _presenceState != previousState;
    }

    // Temporal Confirmation
    _consecutiveValidCount++;
    _rejectionReason = HandRejectionReason.none;

    if (_consecutiveValidCount >= consecutiveConfirmationFrames) {
      _presenceState = HandPresenceState.confirmedHumanHand;
      _confirmedDetection = raw;
    } else {
      _presenceState = HandPresenceState.candidateHand;
      _confirmedDetection = null;
    }

    final stateChanged = _presenceState != previousState;
    return stateChanged || isRealHand;
  }

  /// مسح فوري وكامل — لا يُبقي على أي شيء
  void _immediateClear(HandRejectionReason reason) {
    _consecutiveValidCount = 0;
    _presenceState = HandPresenceState.noHand;
    _confirmedDetection = null;
    _rawDetection = null;
    _rejectionReason = reason;
    _geometryValid = false;
  }

  void reset() {
    _rawDetection = null;
    _confirmedDetection = null;
    _presenceState = HandPresenceState.noHand;
    _consecutiveValidCount = 0;
    _currentFrameId = 0;
    _resultFrameId = 0;
    _isStaleResult = false;
    _geometryValid = false;
    _rejectionReason = HandRejectionReason.noHand;
  }
}
