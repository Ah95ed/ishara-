import 'package:flutter/foundation.dart';
import 'package:ishara/services/pose/sign_state_machine.dart';

/// حالة الحضور المتكاملة للشخص واليد
class PersonPresenceState {
  final bool personPresent;
  final bool bodyPosePresent;
  final bool headPresent;
  final bool facePresent;
  final bool lipsPresent;
  final bool leftHandPresent;
  final bool rightHandPresent;
  final bool handPresent;
  final int personMissingFrames;
  final int handMissingFrames;

  const PersonPresenceState({
    required this.personPresent,
    required this.bodyPosePresent,
    required this.headPresent,
    required this.facePresent,
    required this.lipsPresent,
    required this.leftHandPresent,
    required this.rightHandPresent,
    required this.handPresent,
    required this.personMissingFrames,
    required this.handMissingFrames,
  });

  static const PersonPresenceState initial = PersonPresenceState(
    personPresent: false,
    bodyPosePresent: false,
    headPresent: false,
    facePresent: false,
    lipsPresent: false,
    leftHandPresent: false,
    rightHandPresent: false,
    handPresent: false,
    personMissingFrames: 0,
    handMissingFrames: 0,
  );
}

/// كاشف حضور الشخص واليد المركزي (PersonPresenceDetector)
///
/// يفصل بدقة كاملة بين:
/// 1. Person Detection: (bodyPosePresent || headPresent || facePresent)
/// 2. Hand Detection: (leftHandPresent || rightHandPresent)
/// 3. Sign Detection: (validTemporalMotion)
///
/// يطبق Temporal Persistence:
/// - لا يفقد الشخص بسبب سقوط إطار أو إطارين عابرين (personLostFrameThreshold = 8)
/// - لا يفقد اليد بسبب سقوط إطار عابر (handLostFrameThreshold = 4)
/// - Lips ليست شرطاً لوجود الشخص
/// - يقدم سجلات Debug دقيقة ومطابقة للمواصفات
class PersonPresenceDetector {
  int personLostFrameThreshold;
  int handLostFrameThreshold;

  int _personMissingFrames = 0;
  int _handMissingFrames = 0;

  bool _persistedPersonPresent = false;
  bool _persistedHandPresent = false;

  PersonPresenceState _lastState = PersonPresenceState.initial;

  PersonPresenceDetector({
    this.personLostFrameThreshold = 8,
    this.handLostFrameThreshold = 4,
  });

  PersonPresenceState get currentState => _lastState;
  bool get isPersonPresent => _persistedPersonPresent;
  bool get isHandPresent => _persistedHandPresent;

  /// تقييم حضور الإطار وتطبيق الاستقرار الزمني (Temporal Persistence)
  PersonPresenceState updatePresence({
    required bool bodyPosePresent,
    required bool headPresent,
    required bool facePresent,
    required bool lipsPresent,
    required bool leftHandPresent,
    required bool rightHandPresent,
  }) {
    // 1. Person Detection اللحظي:
    // personPresent must come from body pose only.
    final bool instantPersonDetected = bodyPosePresent;

    // 2. Hand Detection اللحظي:
    // handPresent = leftHandPresent || rightHandPresent
    final bool instantHandDetected = leftHandPresent || rightHandPresent;

    // 3. Temporal Persistence للشخص:
    if (instantPersonDetected) {
      _personMissingFrames = 0;
      _persistedPersonPresent = true;
    } else {
      _personMissingFrames++;
      if (_personMissingFrames >= personLostFrameThreshold) {
        _persistedPersonPresent = false;
      }
    }

    // 4. Temporal Persistence لليد:
    if (instantHandDetected) {
      _handMissingFrames = 0;
      _persistedHandPresent = true;
    } else {
      _handMissingFrames++;
      if (_handMissingFrames >= handLostFrameThreshold) {
        _persistedHandPresent = false;
      }
    }

    _lastState = PersonPresenceState(
      personPresent: _persistedPersonPresent,
      bodyPosePresent: bodyPosePresent,
      headPresent: headPresent,
      facePresent: facePresent,
      lipsPresent: lipsPresent,
      leftHandPresent: leftHandPresent,
      rightHandPresent: rightHandPresent,
      handPresent: _persistedHandPresent,
      personMissingFrames: _personMissingFrames,
      handMissingFrames: _handMissingFrames,
    );

    return _lastState;
  }

  /// طباعة سجلات الـ Debug المطلوبة بالصيغة المحددة تماماً
  void logDebugInfo(SignTemporalState state) {
    if (kDebugMode) {
      debugPrint('PERSON: ${_lastState.personPresent}');
      debugPrint('BODY: ${_lastState.bodyPosePresent}');
      debugPrint('HEAD: ${_lastState.headPresent}');
      debugPrint('FACE: ${_lastState.facePresent}');
      debugPrint('LIPS: ${_lastState.lipsPresent}');
      debugPrint('LEFT HAND: ${_lastState.leftHandPresent}');
      debugPrint('RIGHT HAND: ${_lastState.rightHandPresent}');
      debugPrint('STATE: ${state.name}');
    }
  }

  /// إعادة تعيين العدادات والحالة
  void reset() {
    _personMissingFrames = 0;
    _handMissingFrames = 0;
    _persistedPersonPresent = false;
    _persistedHandPresent = false;
    _lastState = PersonPresenceState.initial;
  }
}
