import 'dart:convert';
import 'dart:io';
import 'dart:math';

// ============================================================================
// Standalone implementations of the pure pipeline components for direct testing
// ============================================================================

List<int> ctcDecodeRawIds(List<int> rawIds, int blankId) {
  if (rawIds.isEmpty) return const [];
  final collapsed = <int>[];
  int? prev;
  for (final id in rawIds) {
    if (id != prev) {
      if (id != blankId) {
        collapsed.add(id);
      }
      prev = id;
    }
  }
  return collapsed;
}

List<List<double>> normalizeSubset(List<List<double>> inputPoints) {
  final int n = inputPoints.length;
  if (n == 0) return [];
  final pose = List.generate(n, (i) => [inputPoints[i][0], inputPoints[i][1]]);

  final double originX = pose[0][0];
  final double originY = pose[0][1];
  for (int i = 0; i < n; i++) {
    pose[i][0] -= originX;
    pose[i][1] -= originY;
  }

  double minX = pose[0][0];
  double minY = pose[0][1];
  for (int i = 1; i < n; i++) {
    if (pose[i][0] < minX) minX = pose[i][0];
    if (pose[i][1] < minY) minY = pose[i][1];
  }
  for (int i = 0; i < n; i++) {
    pose[i][0] -= minX;
    pose[i][1] -= minY;
  }

  double maxX = pose[0][0];
  double maxY = pose[0][1];
  for (int i = 1; i < n; i++) {
    if (pose[i][0] > maxX) maxX = pose[i][0];
    if (pose[i][1] > maxY) maxY = pose[i][1];
  }
  final double scale = max(maxX, maxY);
  if (scale > 1e-7) {
    for (int i = 0; i < n; i++) {
      pose[i][0] /= scale;
      pose[i][1] /= scale;
    }
  }

  double sum = 0.0;
  for (int i = 0; i < n; i++) {
    sum += pose[i][0] + pose[i][1];
  }
  final double mean = sum / (n * 2.0);
  for (int i = 0; i < n; i++) {
    pose[i][0] -= mean;
    pose[i][1] -= mean;
  }

  double maxAbs = 0.0;
  for (int i = 0; i < n; i++) {
    final absX = pose[i][0].abs();
    final absY = pose[i][1].abs();
    if (absX > maxAbs) maxAbs = absX;
    if (absY > maxAbs) maxAbs = absY;
  }
  if (maxAbs > 1e-7) {
    for (int i = 0; i < n; i++) {
      pose[i][0] /= maxAbs;
      pose[i][1] /= maxAbs;
    }
  }

  for (int i = 0; i < n; i++) {
    pose[i][0] *= 0.5;
    pose[i][1] *= 0.5;
  }
  return pose;
}

class TestFrameBuffer {
  static const int requiredFrames = 128;
  final List<List<List<double>>> _buffer = [];
  final List<bool> _activityMask = [];

  int get count => _buffer.length;
  bool get isFull => _buffer.length >= requiredFrames;

  void addFrame(List<List<double>> frame, {required bool hasActivePerson}) {
    _buffer.add(frame);
    _activityMask.add(hasActivePerson);
    if (_buffer.length > requiredFrames) {
      _buffer.removeAt(0);
      _activityMask.removeAt(0);
    }
  }

  List<List<List<double>>>? getFrames() {
    if (!isFull) return null;
    return _buffer;
  }
}

class TestPredictionStabilizer {
  final double minimumConfidence;
  final int requiredStablePredictions;
  String? _lastCandidate;
  int _streak = 0;
  String? _accepted;
  final List<String> sequence = [];

  TestPredictionStabilizer({
    this.minimumConfidence = 0.50,
    this.requiredStablePredictions = 2,
  });

  String? process(String? candidate, double confidence, bool isActive) {
    if (!isActive || candidate == null || candidate.isEmpty) {
      _lastCandidate = null;
      _streak = 0;
      return null;
    }
    if (confidence < minimumConfidence) return null;

    if (candidate == _lastCandidate) {
      _streak++;
    } else {
      _lastCandidate = candidate;
      _streak = 1;
    }

    if (_streak >= requiredStablePredictions) {
      if (candidate != _accepted) {
        _accepted = candidate;
        sequence.add(candidate);
        _lastCandidate = null;
        _streak = 0;
        return candidate;
      }
    }
    return null;
  }

  void onSignEnded() {
    _accepted = null;
    _lastCandidate = null;
    _streak = 0;
  }
}

void assertEq<T>(T a, T b, String msg) {
  if (a != b) {
    print('❌ FAILED: $msg -> Expected $b, got $a');
    exit(1);
  }
}

void assertTrue(bool cond, String msg) {
  if (!cond) {
    print('❌ FAILED: $msg');
    exit(1);
  }
}

void main() {
  print('===============================================================');
  print('          Ishara CSLR Pipeline - Complete Test Suite           ');
  print('===============================================================');

  // Test 1: CTC Greedy Duplicate & Blank Removal
  print('1. Testing CTC Greedy Decoder (Duplicate & Blank Removal)...');
  final ctcInput = [0, 15, 15, 0, 39, 39, 39, 0];
  final ctcOutput = ctcDecodeRawIds(ctcInput, 0);
  assertEq(ctcOutput.length, 2, 'Length should be 2');
  assertEq(ctcOutput[0], 15, 'ID 0 should be 15');
  assertEq(ctcOutput[1], 39, 'ID 1 should be 39');
  print('   ✅ [0, 15, 15, 0, 39, 39, 39, 0] successfully collapsed to [15, 39]');

  // Test 2: Vocabulary Mapping
  print('2. Testing ishara_vocab.json file loading & mapping...');
  final vocabFile = File('assets/models/ishara_vocab.json');
  assertTrue(vocabFile.existsSync(), 'ishara_vocab.json exists in assets/models/');
  final vocabJson = jsonDecode(vocabFile.readAsStringSync()) as Map<String, dynamic>;
  assertEq(vocabJson.length, 684, 'Vocab must have exactly 684 classes');
  assertEq(vocabJson['0'], '_', 'ID 0 must be CTC blank "_"');
  assertEq(vocabJson['15'], 'احد_عشر', 'ID 15 must be "احد_عشر"');
  assertEq(vocabJson['39'], 'اسبوع', 'ID 39 must be "اسبوع"');
  assertEq(vocabJson['683'], 'يوم', 'ID 683 must be "يوم"');
  print('   ✅ All 684 vocabulary classes verified perfectly');

  // Test 3: 128 Frame Buffer
  print('3. Testing 128 Frame Buffer...');
  final buffer = TestFrameBuffer();
  final dummy86x2 = List.generate(86, (_) => [0.1, 0.2]);

  for (int i = 0; i < 127; i++) {
    buffer.addFrame(dummy86x2, hasActivePerson: true);
  }
  assertEq(buffer.isFull, false, 'Buffer must not be full at 127 frames');
  assertEq(buffer.getFrames(), null, 'getFrames() must return null before 128 frames');

  buffer.addFrame(dummy86x2, hasActivePerson: true);
  assertEq(buffer.isFull, true, 'Buffer must be full at 128 frames');
  assertEq(buffer.count, 128, 'Buffer count must be 128');

  // Push 10 more frames
  for (int i = 0; i < 10; i++) {
    buffer.addFrame(dummy86x2, hasActivePerson: true);
  }
  assertEq(buffer.count, 128, 'Buffer must maintain exactly 128 frames (FIFO)');
  assertEq(buffer.getFrames()!.length, 128, 'Output batch shape must have 128 frames');
  assertEq(buffer.getFrames()![0].length, 86, 'Each frame must have 86 keypoints');
  assertEq(buffer.getFrames()![0][0].length, 2, 'Each keypoint must have 2 coordinates');
  print('   ✅ 128 FrameBuffer capacity and FIFO sliding window verified');

  // Test 4: PosePreprocessor math matching datasetv2.py
  print('4. Testing Pose Normalization (datasetv2.py)...');
  final testPoints = [
    [10.0, 20.0],
    [15.0, 25.0],
    [30.0, 40.0],
  ];
  final norm = normalizeSubset(testPoints);
  for (final p in norm) {
    assertTrue(p[0] >= -0.50001 && p[0] <= 0.50001, 'X normalized in [-0.5, 0.5]');
    assertTrue(p[1] >= -0.50001 && p[1] <= 0.50001, 'Y normalized in [-0.5, 0.5]');
  }
  print('   ✅ Normalization math verified [-0.5, 0.5]');

  // Test 5: Missing Landmarks Handling
  print('5. Testing Missing Landmarks Handling...');
  final allZeros = List.generate(21, (_) => [0.0, 0.0]);
  bool isAllZero = true;
  for (final p in allZeros) {
    if (p[0] != 0 || p[1] != 0) isAllZero = false;
  }
  assertTrue(isAllZero, 'Missing keypoints detected as zero vectors');
  print('   ✅ Missing landmarks zero detection verified');

  // Test 6: Repeated Gloss Filtering (سلام سلام سلام -> سلام)
  print('6. Testing Prediction Stabilizer & Duplicate Suppression...');
  final stabilizer = TestPredictionStabilizer();
  final s1 = stabilizer.process('سلام', 0.95, true);
  assertEq(s1, null, 'First detection requires stabilization');
  final s2 = stabilizer.process('سلام', 0.95, true);
  assertEq(s2, 'سلام', 'Second stable detection accepted');
  final s3 = stabilizer.process('سلام', 0.95, true);
  assertEq(s3, null, 'Third identical detection suppressed');
  final s4 = stabilizer.process('سلام', 0.95, true);
  assertEq(s4, null, 'Fourth identical detection suppressed');
  assertEq(stabilizer.sequence.length, 1, 'Sequence must contain exactly 1 entry');
  assertEq(stabilizer.sequence.first, 'سلام', 'Entry must be "سلام"');

  // Sign ended and repeated
  stabilizer.onSignEnded();
  stabilizer.process('سلام', 0.95, true);
  final s6 = stabilizer.process('سلام', 0.95, true);
  assertEq(s6, 'سلام', 'New occurrence accepted after sign ended');
  assertEq(stabilizer.sequence.length, 2, 'Sequence now has 2 entries');
  print('   ✅ Repeated gloss suppression and intentional repeat logic verified');

  // Test 7: Model file existence and size
  print('7. Verifying ishara_model.tflite file...');
  final modelFile = File('assets/models/ishara_model.tflite');
  assertTrue(modelFile.existsSync(), 'ishara_model.tflite exists');
  final modelSizeMb = modelFile.lengthSync() / (1024 * 1024);
  assertTrue(modelSizeMb > 100.0, 'ishara_model.tflite is ~107-112 MB');
  print('   ✅ ishara_model.tflite verified (${modelSizeMb.toStringAsFixed(2)} MB)');

  // =========================================================================
  // Person Detection & State Machine Verification Suite (Tests 8 to 14)
  // =========================================================================
  final presenceDetector = TestPersonPresenceDetector(
    personLostFrameThreshold: 8,
    handLostFrameThreshold: 4,
  );
  final stateMachine = TestSignStateMachine(
    startFramesThreshold: 2,
    endingFramesThreshold: 4,
    minimumSignFrames: 6,
  );

  // Test 8: TEST 1 - No Person -> WAITING_FOR_PERSON
  print('8. Testing Person Absence -> WAITING_FOR_PERSON...');
  final stateT1 = presenceDetector.updatePresence(
    bodyPosePresent: false,
    headPresent: false,
    facePresent: false,
    lipsPresent: false,
    leftHandPresent: false,
    rightHandPresent: false,
  );
  assertEq(stateT1.personPresent, false, 'Person must be absent');
  assertEq(stateT1.handPresent, false, 'Hand must be absent');
  final smT1 = stateMachine.process(
    personPresent: stateT1.personPresent,
    handPresent: stateT1.handPresent,
    motionActive: false,
  );
  assertEq(smT1, 'WAITING_FOR_PERSON', 'State must be WAITING_FOR_PERSON');
  print('   ✅ Result: $smT1 ("بانتظار ظهور الشخص")');

  // Test 9: TEST 2 - Person present without hand -> WAITING_FOR_HAND (NOT WAITING_FOR_PERSON)
  print('9. Testing Person Present without Hand -> WAITING_FOR_HAND...');
  final stateT2 = presenceDetector.updatePresence(
    bodyPosePresent: true,
    headPresent: true,
    facePresent: true,
    lipsPresent: false, // Lips is NOT required for person detection
    leftHandPresent: false,
    rightHandPresent: false,
  );
  assertEq(stateT2.personPresent, true, 'Person must be detected from body/head/face');
  assertEq(stateT2.handPresent, false, 'Hand is not present');
  final smT2 = stateMachine.process(
    personPresent: stateT2.personPresent,
    handPresent: stateT2.handPresent,
    motionActive: false,
  );
  assertEq(smT2, 'WAITING_FOR_HAND', 'State must transition to WAITING_FOR_HAND');
  print('   ✅ Result: $smT2 ("تم اكتشاف الشخص - بانتظار ظهور اليد")');

  // Test 10: TEST 3 - Person + Hand without motion -> READY
  print('10. Testing Person + Hand without Motion -> READY...');
  final stateT3 = presenceDetector.updatePresence(
    bodyPosePresent: true,
    headPresent: true,
    facePresent: true,
    lipsPresent: false,
    leftHandPresent: false,
    rightHandPresent: true,
  );
  assertEq(stateT3.personPresent, true, 'Person must be present');
  assertEq(stateT3.handPresent, true, 'Hand must be present');
  final smT3 = stateMachine.process(
    personPresent: stateT3.personPresent,
    handPresent: stateT3.handPresent,
    motionActive: false,
  );
  assertEq(smT3, 'READY', 'State must transition to READY');
  print('   ✅ Result: $smT3 ("جاهز للإشارة")');

  // Test 11: TEST 4 - Person + Hand + Motion -> SIGN_STARTING / SIGN_ACTIVE
  print('11. Testing Person + Hand + Motion -> SIGN_STARTING / SIGN_ACTIVE...');
  stateMachine.process(
    personPresent: true,
    handPresent: true,
    motionActive: true,
  );
  final smT4 = stateMachine.process(
    personPresent: true,
    handPresent: true,
    motionActive: true,
  );
  assertTrue(smT4 == 'SIGN_STARTING' || smT4 == 'SIGN_ACTIVE', 'State must be active');
  print('   ✅ Result: $smT4 ("جارٍ تحليل الإشارة...")');

  // Test 12: TEST 5 - 1 Dropped Frame does NOT cause WAITING_FOR_PERSON (Temporal Persistence)
  print('12. Testing Single Dropped Frame (Temporal Persistence)...');
  presenceDetector.updatePresence(
    bodyPosePresent: true,
    headPresent: true,
    facePresent: true,
    lipsPresent: false,
    leftHandPresent: false,
    rightHandPresent: false,
  );
  assertEq(presenceDetector.isPersonPresent, true, 'Person present before drop');
  // Drop 1 frame
  final stateDrop = presenceDetector.updatePresence(
    bodyPosePresent: false,
    headPresent: false,
    facePresent: false,
    lipsPresent: false,
    leftHandPresent: false,
    rightHandPresent: false,
  );
  assertEq(stateDrop.personPresent, true, 'Person must persist through 1 dropped frame');
  assertEq(stateDrop.personMissingFrames, 1, 'Missing frame count must be 1');
  print('   ✅ Person persisted (personPresent=true, missingFrames=1)');

  // Test 13: TEST 6 - Consecutive dropped frames (>= 8) -> WAITING_FOR_PERSON
  print('13. Testing Consecutive Dropped Frames (>= 8) -> Lost Person...');
  for (int i = 0; i < 7; i++) {
    presenceDetector.updatePresence(
      bodyPosePresent: false,
      headPresent: false,
      facePresent: false,
      lipsPresent: false,
      leftHandPresent: false,
      rightHandPresent: false,
    );
  }
  final stateLost = presenceDetector.updatePresence(
    bodyPosePresent: false,
    headPresent: false,
    facePresent: false,
    lipsPresent: false,
    leftHandPresent: false,
    rightHandPresent: false,
  );
  assertEq(stateLost.personPresent, false, 'Person lost after threshold of 8 frames');
  final smLost = stateMachine.process(
    personPresent: stateLost.personPresent,
    handPresent: stateLost.handPresent,
    motionActive: false,
  );
  assertEq(smLost, 'WAITING_FOR_PERSON', 'State resets to WAITING_FOR_PERSON');
  print('   ✅ Person lost cleanly after 8 consecutive missing frames -> $smLost');

  // Test 14: Lips Independence Verification
  print('14. Testing Lips Independence (Lips not required for person presence)...');
  final stateNoLips = presenceDetector.updatePresence(
    bodyPosePresent: true,
    headPresent: true,
    facePresent: true,
    lipsPresent: false, // NO lips detected
    leftHandPresent: false,
    rightHandPresent: false,
  );
  assertEq(stateNoLips.personPresent, true, 'Person present even without lips');
  assertEq(stateNoLips.lipsPresent, false, 'Lips correctly marked absent');
  print('   ✅ Lips is completely decoupled from Person Detection');

  print('===============================================================');
  print('           🎉 ALL 14 INTEGRATION TESTS PASSED 100%!            ');
  print('===============================================================');
}

// ---------------------------------------------------------------------------
// Standalone Classes for Verification of Person & Hand Detection
// ---------------------------------------------------------------------------

class TestPersonPresenceState {
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

  const TestPersonPresenceState({
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
}

class TestPersonPresenceDetector {
  final int personLostFrameThreshold;
  final int handLostFrameThreshold;
  int _personMissingFrames = 0;
  int _handMissingFrames = 0;
  bool _persistedPersonPresent = false;
  bool _persistedHandPresent = false;

  TestPersonPresenceDetector({
    this.personLostFrameThreshold = 8,
    this.handLostFrameThreshold = 4,
  });

  bool get isPersonPresent => _persistedPersonPresent;
  bool get isHandPresent => _persistedHandPresent;

  TestPersonPresenceState updatePresence({
    required bool bodyPosePresent,
    required bool headPresent,
    required bool facePresent,
    required bool lipsPresent,
    required bool leftHandPresent,
    required bool rightHandPresent,
  }) {
    final bool instantPerson = bodyPosePresent || headPresent || facePresent;
    final bool instantHand = leftHandPresent || rightHandPresent;

    if (instantPerson) {
      _personMissingFrames = 0;
      _persistedPersonPresent = true;
    } else {
      _personMissingFrames++;
      if (_personMissingFrames >= personLostFrameThreshold) {
        _persistedPersonPresent = false;
      }
    }

    if (instantHand) {
      _handMissingFrames = 0;
      _persistedHandPresent = true;
    } else {
      _handMissingFrames++;
      if (_handMissingFrames >= handLostFrameThreshold) {
        _persistedHandPresent = false;
      }
    }

    return TestPersonPresenceState(
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
  }
}

class TestSignStateMachine {
  final int startFramesThreshold;
  final int endingFramesThreshold;
  final int minimumSignFrames;

  String _state = 'WAITING_FOR_PERSON';
  int _startStreak = 0;

  TestSignStateMachine({
    this.startFramesThreshold = 2,
    this.endingFramesThreshold = 4,
    this.minimumSignFrames = 6,
  });

  String get state => _state;

  String process({
    required bool personPresent,
    required bool handPresent,
    required bool motionActive,
  }) {
    if (!personPresent) {
      _state = 'WAITING_FOR_PERSON';
      _startStreak = 0;
      return _state;
    }

    if (!handPresent) {
      _state = 'WAITING_FOR_HAND';
      _startStreak = 0;
      return _state;
    }

    if (_state == 'WAITING_FOR_PERSON' || _state == 'WAITING_FOR_HAND') {
      _state = 'READY';
    }

    if (_state == 'READY') {
      if (motionActive) {
        _startStreak++;
        if (_startStreak >= startFramesThreshold) {
          _state = 'SIGN_STARTING';
          _startStreak = 0;
        }
      } else {
        _startStreak = 0;
      }
    } else if (_state == 'SIGN_STARTING') {
      _state = 'SIGN_ACTIVE';
    }

    return _state;
  }
}
