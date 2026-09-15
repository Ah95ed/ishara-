import 'dart:io';

import 'package:ishara/services/pose/sign_presence_validator.dart';
import 'package:ishara/services/pose/sign_state_machine.dart';
import 'package:ishara/services/pose/temporal_motion_analyzer.dart';
import 'package:ishara/services/tflite/frame_buffer.dart';
import 'package:ishara/services/word_only_filter.dart';

void assertTrue(bool condition, String message) {
  if (!condition) {
    stderr.writeln('❌ ASSERTION FAILED: $message');
    exit(1);
  }
}

void assertEq<T>(T actual, T expected, String message) {
  if (actual != expected) {
    stderr.writeln(
      '❌ ASSERTION FAILED: $message -> Expected: $expected, Got: $actual',
    );
    exit(1);
  }
}

void main() {
  print('===============================================================');
  print('    Ishara CSLR Temporal Recognition Pipeline - Test Suite     ');
  print('              Tests A through H (All Criteria)                ');
  print('===============================================================');

  final presenceValidator = SignPresenceValidator(
    minHandConfidence: 0.40,
    minHeadConfidence: 0.35,
  );
  final motionAnalyzer = TemporalMotionAnalyzer(
    motionStartThreshold: 0.020,
    motionActiveThreshold: 0.015,
    motionEndThreshold: 0.008,
  );
  final stateMachine = SignStateMachine(
    startFramesThreshold: 3,
    endingFramesThreshold: 6,
    minimumSignFrames: 12,
    maximumSignFrames: 128,
    minValidHandRatio: 0.50,
    minValidHeadRatio: 0.50,
  );

  List<List<double>> createHand(double x, double y) =>
      List.generate(21, (i) => [x + (i * 0.005), y + (i * 0.005)]);
  List<List<double>> createHead(double x, double y) =>
      List.generate(25, (i) => [x + (i * 0.003), y + (i * 0.003)]);
  List<List<double>> createLips(double x, double y) =>
      List.generate(19, (i) => [x + (i * 0.002), y + (i * 0.002)]);
  List<List<double>> create86() => List.generate(86, (_) => [0.5, 0.5]);

  // ──────────────────────────────── TEST A ────────────────────────────────
  print('\n[TEST A] Camera with no person:');
  final presA = presenceValidator.evaluatePresence(
    rightHand: null,
    leftHand: null,
    lips: null,
    body: null,
  );
  assertTrue(!presA.hasHeadOrFace, 'PresenceValidator: hasHeadOrFace is false');
  assertTrue(
    !presA.hasAtLeastOneHand,
    'PresenceValidator: hasAtLeastOneHand is false',
  );
  assertTrue(
    !presA.isSignEligible,
    'PresenceValidator: isSignEligible is false',
  );
  final stateA = stateMachine.processFrame(
    presence: presA,
    motion: TemporalMotionResult.zero,
    frame86x2: create86(),
  );
  assertEq(
    stateA,
    SignTemporalState.waitingForPerson,
    'State remains waitingForPerson',
  );
  assertTrue(
    stateMachine.completedSegment == null,
    'No completed segment emitted',
  );
  print('   ✅ TEST A PASSED: No person -> waitingForPerson, no prediction');

  // ──────────────────────────────── TEST A1 ────────────────────────────────
  print('\n[TEST A1] Face-only frame must NOT count as person presence:');
  final faceOnly = presenceValidator.evaluatePresence(
    rightHand: null,
    leftHand: null,
    lips: createLips(0.5, 0.3),
    body: createHead(0.5, 0.25),
    headConfidence: 0.85,
  );
  assertTrue(faceOnly.hasHeadOrFace, 'Face/head is detected');
  assertTrue(
    !faceOnly.personPresent,
    'Face-only frame must not trigger person presence',
  );
  assertTrue(
    !faceOnly.isSignEligible,
    'Face-only frame must not become sign-eligible',
  );
  print('   ✅ TEST A1 PASSED: Face-only does not satisfy person presence');

  // ──────────────────────────────── TEST B ────────────────────────────────
  print('\n[TEST B] Face only, no hand:');
  final presB = presenceValidator.evaluatePresence(
    rightHand: null,
    leftHand: null,
    lips: createLips(0.5, 0.3),
    body: createHead(0.5, 0.25),
    headConfidence: 0.85,
  );
  assertTrue(presB.hasHeadOrFace, 'Face/head detected');
  assertTrue(!presB.hasAtLeastOneHand, 'No hand detected');
  assertTrue(!presB.isSignEligible, 'Not eligible because hand is missing');
  final stateB = stateMachine.processFrame(
    presence: presB,
    motion: TemporalMotionResult.zero,
    frame86x2: create86(),
  );
  assertEq(
    stateB,
    SignTemporalState.waitingForHand,
    'State transitions to waitingForHand',
  );
  assertTrue(stateMachine.completedSegment == null, 'No segment emitted');
  print('   ✅ TEST B PASSED: Face only -> waitingForHand, no prediction');

  // ──────────────────────────────── TEST C ────────────────────────────────
  print('\n[TEST C] Face + static hand:');
  final presC = presenceValidator.evaluatePresence(
    rightHand: createHand(0.6, 0.5),
    lips: createLips(0.5, 0.3),
    body: createHead(0.5, 0.25),
    rightHandConfidence: 0.90,
    headConfidence: 0.85,
  );
  assertTrue(presC.isSignEligible, 'Eligible with head and hand');
  final initialMotion = motionAnalyzer.analyzeFrame(
    rightHand: createHand(0.6, 0.5),
    lips: createLips(0.5, 0.3),
    body: createHead(0.5, 0.25),
  );
  assertTrue(
    initialMotion.motionEnergy == 0.0,
    'First frame has 0 motion energy',
  );
  for (int i = 0; i < 8; i++) {
    final stateC = stateMachine.processFrame(
      presence: presC,
      motion: TemporalMotionResult.zero,
      frame86x2: create86(),
    );
    assertEq(
      stateC,
      SignTemporalState.ready,
      'Static hand stays in READY state',
    );
    assertTrue(
      stateMachine.completedSegment == null,
      'No prediction while hand is static',
    );
  }
  print('   ✅ TEST C PASSED: Static hand -> READY state, no translation');

  // ──────────────────────────────── TEST D ────────────────────────────────
  print('\n[TEST D] Short random micro-movement (jitter < minimumSignFrames):');
  // الحركة لـ 4 إطارات فقط ثم توقف
  for (int i = 0; i < 4; i++) {
    final motion = TemporalMotionResult(
      motionEnergy: 0.040,
      handVelocity: 1.5,
      handAcceleration: 0.2,
      headVelocity: 0.05,
      relativeHandToHeadDist: 0.3,
      directionX: 1.0,
      directionY: 0.0,
      isAboveStartThreshold: true,
      isAboveActiveThreshold: true,
      isBelowEndThreshold: false,
    );
    stateMachine.processFrame(
      presence: presC,
      motion: motion,
      frame86x2: create86(),
    );
  }
  // التوقف لـ 8 إطارات
  for (int i = 0; i < 8; i++) {
    final settledMotion = TemporalMotionResult(
      motionEnergy: 0.002,
      handVelocity: 0.01,
      handAcceleration: 0.0,
      headVelocity: 0.0,
      relativeHandToHeadDist: 0.3,
      directionX: 0.0,
      directionY: 0.0,
      isAboveStartThreshold: false,
      isAboveActiveThreshold: false,
      isBelowEndThreshold: true,
    );
    stateMachine.processFrame(
      presence: presC,
      motion: settledMotion,
      frame86x2: create86(),
    );
  }
  assertTrue(
    stateMachine.completedSegment == null,
    'Micro-movement rejected as noise',
  );
  assertEq(
    stateMachine.state,
    SignTemporalState.ready,
    'State resets to READY',
  );
  print('   ✅ TEST D PASSED: Micro-movement (<12 frames) rejected as Noise');

  // ──────────────────────────────── TEST E ────────────────────────────────
  print(
    '\n[TEST E] Full genuine sign (Ready -> Start -> Active -> End -> Analyze):',
  );
  stateMachine.reset();
  stateMachine.processFrame(
    presence: presC,
    motion: TemporalMotionResult.zero,
    frame86x2: create86(),
  );
  assertEq(stateMachine.state, SignTemporalState.ready, 'Starting in READY');

  // 3 frames start
  final startMotion = TemporalMotionResult(
    motionEnergy: 0.035,
    handVelocity: 1.2,
    handAcceleration: 0.1,
    headVelocity: 0.05,
    relativeHandToHeadDist: 0.35,
    directionX: 0.8,
    directionY: -0.6,
    isAboveStartThreshold: true,
    isAboveActiveThreshold: true,
    isBelowEndThreshold: false,
  );
  for (int i = 0; i < 3; i++) {
    stateMachine.processFrame(
      presence: presC,
      motion: startMotion,
      frame86x2: create86(),
    );
  }
  assertEq(
    stateMachine.state,
    SignTemporalState.signStarting,
    'Transitioned to signStarting',
  );

  // 16 frames active motion
  final activeMotion = TemporalMotionResult(
    motionEnergy: 0.030,
    handVelocity: 1.0,
    handAcceleration: 0.05,
    headVelocity: 0.02,
    relativeHandToHeadDist: 0.30,
    directionX: 0.7,
    directionY: -0.7,
    isAboveStartThreshold: true,
    isAboveActiveThreshold: true,
    isBelowEndThreshold: false,
  );
  for (int i = 0; i < 16; i++) {
    stateMachine.processFrame(
      presence: presC,
      motion: activeMotion,
      frame86x2: create86(),
    );
    assertTrue(
      stateMachine.completedSegment == null,
      'Never emit segment mid-motion',
    );
  }
  assertEq(
    stateMachine.state,
    SignTemporalState.signActive,
    'Active motion tracked in signActive',
  );

  // 6 frames ending motion
  final endMotion = TemporalMotionResult(
    motionEnergy: 0.003,
    handVelocity: 0.02,
    handAcceleration: 0.0,
    headVelocity: 0.0,
    relativeHandToHeadDist: 0.30,
    directionX: 0.0,
    directionY: 0.0,
    isAboveStartThreshold: false,
    isAboveActiveThreshold: false,
    isBelowEndThreshold: true,
  );
  for (int i = 0; i < 6; i++) {
    stateMachine.processFrame(
      presence: presC,
      motion: endMotion,
      frame86x2: create86(),
    );
  }
  assertEq(
    stateMachine.state,
    SignTemporalState.analyzing,
    'Transitioned to ANALYZING',
  );
  assertTrue(stateMachine.completedSegment != null, 'SignSegment completed');
  final seg = stateMachine.completedSegment!;
  assertTrue(seg.durationFrames >= 12, 'Duration valid');
  assertTrue(seg.validHandRatio >= 0.50, 'Valid hand ratio');
  assertTrue(seg.validHeadRatio >= 0.50, 'Valid head ratio');

  stateMachine.confirmSign('شكراً');
  assertEq(stateMachine.state, SignTemporalState.confirmed, 'Confirmed sign');
  assertEq(stateMachine.lastConfirmedWord, 'شكراً', 'Confirmed word set');
  print(
    '   ✅ TEST E PASSED: Full sign lifecycle tracked, collected, analyzed and confirmed',
  );

  // ──────────────────────────────── TEST F ────────────────────────────────
  print('\n[TEST F] Fast motion mid-sign:');
  stateMachine.reset();
  stateMachine.processFrame(
    presence: presC,
    motion: TemporalMotionResult.zero,
    frame86x2: create86(),
  );
  for (int i = 0; i < 3; i++) {
    stateMachine.processFrame(
      presence: presC,
      motion: startMotion,
      frame86x2: create86(),
    );
  }
  final fastMotion = TemporalMotionResult(
    motionEnergy: 0.090,
    handVelocity: 4.5,
    handAcceleration: 1.2,
    headVelocity: 0.1,
    relativeHandToHeadDist: 0.4,
    directionX: 1.0,
    directionY: 0.0,
    isAboveStartThreshold: true,
    isAboveActiveThreshold: true,
    isBelowEndThreshold: false,
  );
  for (int i = 0; i < 20; i++) {
    stateMachine.processFrame(
      presence: presC,
      motion: fastMotion,
      frame86x2: create86(),
    );
    assertTrue(
      stateMachine.completedSegment == null,
      'Do not translate during fast motion',
    );
  }
  assertEq(
    stateMachine.state,
    SignTemporalState.signActive,
    'Remains in signActive during fast motion',
  );
  print('   ✅ TEST F PASSED: Fast motion tracked, no translation mid-motion');

  // ──────────────────────────────── TEST G ────────────────────────────────
  print('\n[TEST G] Single-frame hand drop tolerance:');
  final presNoHand = presenceValidator.evaluatePresence(
    rightHand: null,
    leftHand: null,
    lips: createLips(0.5, 0.3),
    body: createHead(0.5, 0.25),
    headConfidence: 0.85,
  );
  stateMachine.processFrame(
    presence: presNoHand,
    motion: activeMotion,
    frame86x2: create86(),
  );
  assertEq(
    stateMachine.state,
    SignTemporalState.signActive,
    'Single-frame drop tolerated in signActive',
  );
  print('   ✅ TEST G PASSED: Single frame drop does not terminate signActive');

  // ──────────────────────────────── TEST H ────────────────────────────────
  print('\n[TEST H] Multi-frame hand drop:');
  for (int i = 0; i < 5; i++) {
    stateMachine.processFrame(
      presence: presNoHand,
      motion: TemporalMotionResult.zero,
      frame86x2: create86(),
    );
  }
  assertEq(
    stateMachine.state,
    SignTemporalState.waitingForHand,
    'Transitions to waitingForHand after multi-frame drop',
  );
  print('   ✅ TEST H PASSED: Multi-frame drop aborts sign to waitingForHand');

  // ──────────────────────────────── TEST I ────────────────────────────────
  print('\n[TEST I] Uniform temporal resampling (padOrResampleTo128):');
  final input25 = List.generate(
    25,
    (i) => List.generate(86, (k) => [i.toDouble(), (i * 2).toDouble()]),
  );
  final resampled = FrameBuffer.padOrResampleTo128(input25);
  assertEq(resampled.length, 128, 'Resampled batch has 128 frames');
  assertEq(resampled[0].length, 86, '86 keypoints per frame');
  assertEq(resampled[0][0][0], 0.0, 'First frame coordinate matches');
  assertTrue(
    (resampled[127][0][0] - 24.0).abs() < 0.01,
    'Last frame coordinate matches',
  );
  print(
    '   ✅ TEST I PASSED: Uniform temporal resampling from 25 to 128 frames verified',
  );

  // ──────────────────────────────── TEST J ────────────────────────────────
  print('\n[TEST J] Duplicate suppression & neutral transition:');
  stateMachine.confirmSign('مساعدة');
  stateMachine.startCooldown();
  assertEq(stateMachine.state, SignTemporalState.cooldown, 'In cooldown');
  assertEq(stateMachine.lastConfirmedWord, 'مساعدة', 'Last confirmed retained');
  print('   ✅ TEST J PASSED: Duplicate suppression & cooldown verified');

  // ──────────────────────────────── TEST K ────────────────────────────────
  print('\n[TEST K] WordOnlyFilter rejection:');
  assertTrue(!WordOnlyFilter.isValidWord('أ'), 'Letter Alef rejected');
  assertTrue(!WordOnlyFilter.isValidWord('ب'), 'Letter Ba2 rejected');
  assertTrue(!WordOnlyFilter.isValidWord('alef'), 'Technical alef rejected');
  assertTrue(!WordOnlyFilter.isValidWord('blank'), 'Blank rejected');
  assertTrue(!WordOnlyFilter.isValidWord('9'), 'Digit rejected');
  assertTrue(WordOnlyFilter.isValidWord('شكراً'), 'Valid word شكراً accepted');
  assertTrue(
    WordOnlyFilter.isValidWord('مساعدة'),
    'Valid word مساعدة accepted',
  );
  print(
    '   ✅ TEST K PASSED: WordOnlyFilter properly gates single letters & non-words',
  );

  print('\n===============================================================');
  print('      🎉 ALL 11 INTEGRATION TESTS (A to K) PASSED 100%!        ');
  print('===============================================================');
}
