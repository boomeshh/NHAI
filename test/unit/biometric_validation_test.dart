import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/auth_engine/auth_engine_impl.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_interface.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/core/validation/biometric_validation.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────
FaceObservation obs({
  bool faceDetected = true,
  double leftEyeOpen = 0.9,
  double rightEyeOpen = 0.9,
  double yaw = 2.0,
  double roll = 2.0,
  bool hasLeftEye = true,
  bool hasRightEye = true,
  bool hasNoseBase = true,
  bool hasLeftCheek = true,
  bool hasRightCheek = true,
}) =>
    FaceObservation(
      faceDetected: faceDetected,
      leftEyeOpen: leftEyeOpen,
      rightEyeOpen: rightEyeOpen,
      yaw: yaw,
      roll: roll,
      hasLeftEye: hasLeftEye,
      hasRightEye: hasRightEye,
      hasNoseBase: hasNoseBase,
      hasLeftCheek: hasLeftCheek,
      hasRightCheek: hasRightCheek,
    );

class _Storage implements StorageManagerInterface {
  final List<EmployeeRecord> records;
  _Storage(this.records);
  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async => records;
  @override
  Future<void> saveEmployeeRecord(EmployeeRecord r) async {}
  @override
  Future<EmployeeRecord?> getEmployeeRecord(String id) async => null;
  @override
  Future<bool> employeeExists(String id) async => false;
  @override
  Future<void> deleteEmployeeRecord(String id) async {}
  @override
  Future<void> logAuthAttempt(AuthLogEntry e) async {}
  @override
  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async => [];
  @override
  Future<void> logStorageError(String m) async {}
}

class _Liveness implements LivenessDetectorInterface {
  @override
  Future<LivenessResult> detectLiveness(Stream<CameraFrame> s) async =>
      LivenessResult.confirmed;
}

class _FixedEngine extends AuthEngineImpl {
  final List<double> embedding;
  _FixedEngine(StorageManagerInterface s, this.embedding, {double? threshold})
      : super(
          storage: s,
          livenessDetector: _Liveness(),
          livenessEnabled: false,
          verificationThreshold:
              threshold ?? AuthEngineImpl.defaultVerificationThreshold,
        );
  @override
  Future<FaceEmbedding> runInference(CameraFrame frame) async =>
      FaceEmbedding(embedding);
}

EmployeeRecord _rec(String id, List<double> emb) => EmployeeRecord(
      employeeId: id,
      name: 'N',
      department: 'D',
      embedding: FaceEmbedding(emb),
      enrolledAt: DateTime.utc(2026, 1, 1),
    );

CameraFrame _frame() => const CameraFrame(
    bytes: [1, 2, 3], width: 112, height: 112, sharpnessScore: 50.0);

void main() {
  const validator = FaceValidator();

  // ── Tests 1–8: single-frame validation ────────────────────────────────────
  test('Test 1: face visible, eyes open, head straight → PASS', () {
    final r = validator.validate(obs());
    expect(r.valid, isTrue);
    expect(r.failure, ValidationFailure.none);
  });

  test('Test 2: left eye closed → FAIL', () {
    final r = validator.validate(obs(leftEyeOpen: 0.2));
    expect(r.valid, isFalse);
    expect(r.failure, ValidationFailure.eyesClosed);
    expect(r.message, kMsgEyesClosed);
  });

  test('Test 3: right eye closed → FAIL', () {
    expect(validator.validate(obs(rightEyeOpen: 0.2)).failure,
        ValidationFailure.eyesClosed);
  });

  test('Test 4: both eyes closed → FAIL', () {
    expect(
        validator.validate(obs(leftEyeOpen: 0.1, rightEyeOpen: 0.1)).failure,
        ValidationFailure.eyesClosed);
  });

  test('Test 5: hand covering nose (no nose landmark) → FAIL (occluded)', () {
    final r = validator.validate(obs(hasNoseBase: false));
    expect(r.valid, isFalse);
    expect(r.failure, ValidationFailure.occluded);
    expect(r.message, kMsgOccluded);
  });

  test('Test 6: hand covering eye (no eye landmark) → FAIL (occluded)', () {
    expect(validator.validate(obs(hasLeftEye: false)).failure,
        ValidationFailure.occluded);
  });

  test('Test 7: yaw = 20° → FAIL (head pose)', () {
    final r = validator.validate(obs(yaw: 20));
    expect(r.failure, ValidationFailure.headPose);
    expect(r.message, kMsgHeadPose);
  });

  test('Test 8: roll = 20° → FAIL (head pose)', () {
    expect(validator.validate(obs(roll: 20)).failure,
        ValidationFailure.headPose);
  });

  // ── Tests 9–10: threshold (default 0.85) ──────────────────────────────────
  test('Test 9: similarity 0.74 → FAIL', () {
    final engine = AuthEngineImpl(
        storage: _Storage([]), livenessDetector: _Liveness());
    expect(engine.classify(0.74), AuthClassification.failed);
  });

  test('Test 10: similarity = threshold (0.85) → PASS', () {
    final engine = AuthEngineImpl(
        storage: _Storage([]), livenessDetector: _Liveness());
    expect(engine.verificationThreshold, 0.85);
    expect(engine.classify(0.85), AuthClassification.verified);
  });

  // ── Tests 11–12: blink liveness ───────────────────────────────────────────
  test('Test 11: blink Open→Closed→Open → PASS', () {
    final b = BlinkLivenessTracker();
    b.record(0.85); // open
    b.record(0.20); // closed
    b.record(0.85); // open again
    expect(b.blinkDetected, isTrue);
  });

  test('Test 12: no blink → FAIL', () {
    final b = BlinkLivenessTracker();
    b.record(0.85);
    b.record(0.80);
    b.record(0.85);
    expect(b.blinkDetected, isFalse);
  });

  // ── Tests 13–14: multi-frame stability ────────────────────────────────────
  test('Test 13: only 2 valid frames → FAIL (not stable)', () {
    final t = FrameStabilityTracker();
    t.record(true);
    t.record(true);
    expect(t.isStable, isFalse);
  });

  test('Test 14: 3 valid frames → PASS (stable)', () {
    final t = FrameStabilityTracker();
    t.record(true);
    t.record(true);
    t.record(true);
    expect(t.isStable, isTrue);
  });

  test('stability: an invalid frame resets the counter', () {
    final t = FrameStabilityTracker();
    t.record(true);
    t.record(true);
    t.record(false);
    expect(t.consecutiveValid, 0);
    expect(t.isStable, isFalse);
  });

  // ── Test 15: trust score == similarity × 100 (no random logic) ────────────
  test('Test 15: trustScore equals similarity × 100 (deterministic)', () async {
    final vec = List<double>.filled(128, 0.5);
    final engine = _FixedEngine(_Storage([_rec('A', vec)]), vec);
    final r1 = await engine.authenticate(_frame());
    final r2 = await engine.authenticate(_frame());
    // Identical embeddings → cosine 1.0 → trustScore 1.0 → 100%.
    expect(r1.trustScore, closeTo(1.0, 1e-9));
    expect((r1.trustScore * 100).round(), 100);
    // Deterministic: same inputs → same score (no randomness).
    expect(r1.trustScore, equals(r2.trustScore));
  });

  // ── BiometricGate end-to-end flow (composition) ───────────────────────────
  group('BiometricGate', () {
    test('3 valid frames + blink → passed', () {
      final gate = BiometricGate(requiredFrames: 3, requireBlink: true);
      expect(gate.process(obs()).passed, isFalse); // 1
      expect(gate.process(obs()).passed, isFalse); // 2
      final r3 = gate.process(obs()); // 3 → awaiting blink
      expect(r3.passed, isFalse);
      expect(r3.message, kMsgBlink);
      gate.process(obs(leftEyeOpen: 0.2, rightEyeOpen: 0.2)); // closed
      final done = gate.process(obs()); // reopen → blink
      expect(done.passed, isTrue);
      expect(done.blinkDetected, isTrue);
    });

    test('invalid frame mid-collection resets stability', () {
      final gate = BiometricGate(requiredFrames: 3, requireBlink: false);
      gate.process(obs());
      gate.process(obs());
      final bad = gate.process(obs(yaw: 30)); // invalid → reset
      expect(bad.passed, isFalse);
      expect(bad.message, kMsgHeadPose);
      expect(gate.process(obs()).validFrames, 1);
    });

    test('without blink requirement, 3 valid frames → passed', () {
      final gate = BiometricGate(requiredFrames: 3, requireBlink: false);
      gate.process(obs());
      gate.process(obs());
      expect(gate.process(obs()).passed, isTrue);
    });
  });
}
