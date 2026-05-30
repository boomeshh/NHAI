/// Pure-Dart biometric validation gates (no I/O, no native bindings).
///
/// Covers: eye-open validation (Phase 2), occlusion detection (Phase 3),
/// head-pose validation (Phase 4), multi-frame stability (Phase 5) and blink
/// liveness (Phase 6). All thresholds are constants; all logic is deterministic
/// and unit-testable.
library;

// ── User-facing messages (Phase 10 — never show technical text) ──────────────
const String kMsgNoFace = 'Position your face within the guide';
const String kMsgOccluded = 'Remove objects covering your face';
const String kMsgEyesClosed = 'Please open both eyes';
const String kMsgHeadPose = 'Look directly at the camera';
const String kMsgBlink = 'Please blink once';
const String kMsgHold = 'Hold still…';

/// Per-frame signals extracted from a detected face.
class FaceObservation {
  final bool faceDetected;

  /// ML Kit eye-open probabilities in [0, 1].
  final double leftEyeOpen;
  final double rightEyeOpen;

  /// Head Euler angles in degrees (yaw = Y, roll = Z).
  final double yaw;
  final double roll;

  /// Presence of the five critical landmarks (Phase 3).
  final bool hasLeftEye;
  final bool hasRightEye;
  final bool hasNoseBase;
  final bool hasLeftCheek;
  final bool hasRightCheek;

  const FaceObservation({
    required this.faceDetected,
    required this.leftEyeOpen,
    required this.rightEyeOpen,
    required this.yaw,
    required this.roll,
    required this.hasLeftEye,
    required this.hasRightEye,
    required this.hasNoseBase,
    required this.hasLeftCheek,
    required this.hasRightCheek,
  });

  bool get allCriticalLandmarksPresent =>
      hasLeftEye && hasRightEye && hasNoseBase && hasLeftCheek && hasRightCheek;

  /// The lower of the two eye-open probabilities (used for blink tracking).
  double get minEyeOpen => leftEyeOpen < rightEyeOpen ? leftEyeOpen : rightEyeOpen;
}

enum ValidationFailure { none, noFace, occluded, eyesClosed, headPose }

class FaceValidationResult {
  final bool valid;
  final ValidationFailure failure;
  final String message;
  const FaceValidationResult(this.valid, this.failure, this.message);
}

/// Single-frame face-quality validator (Phases 2, 3, 4).
class FaceValidator {
  /// Phase 2: reject if either eye-open probability is below this.
  static const double eyeOpenMinProbability = 0.60;

  /// Phase 4: max absolute yaw / roll in degrees.
  static const double maxYawDegrees = 15.0;
  static const double maxRollDegrees = 15.0;

  const FaceValidator();

  FaceValidationResult validate(FaceObservation o) {
    if (!o.faceDetected) {
      return const FaceValidationResult(
          false, ValidationFailure.noFace, kMsgNoFace);
    }
    // Phase 3 — occlusion: any missing critical landmark.
    if (!o.allCriticalLandmarksPresent) {
      return const FaceValidationResult(
          false, ValidationFailure.occluded, kMsgOccluded);
    }
    // Phase 2 — both eyes must be open.
    if (o.leftEyeOpen < eyeOpenMinProbability ||
        o.rightEyeOpen < eyeOpenMinProbability) {
      return const FaceValidationResult(
          false, ValidationFailure.eyesClosed, kMsgEyesClosed);
    }
    // Phase 4 — head pose.
    if (o.yaw.abs() > maxYawDegrees || o.roll.abs() > maxRollDegrees) {
      return const FaceValidationResult(
          false, ValidationFailure.headPose, kMsgHeadPose);
    }
    return const FaceValidationResult(true, ValidationFailure.none, kMsgHold);
  }
}

/// Phase 5 — requires N consecutive valid frames; any invalid frame resets.
class FrameStabilityTracker {
  final int requiredConsecutive;
  int _consecutive = 0;

  FrameStabilityTracker({this.requiredConsecutive = 3});

  int get consecutiveValid => _consecutive;
  bool get isStable => _consecutive >= requiredConsecutive;

  void record(bool valid) => _consecutive = valid ? _consecutive + 1 : 0;
  void reset() => _consecutive = 0;
}

/// Phase 6 — blink liveness: detects Open → Closed → Open using eye-open
/// probabilities. Open when > [openThreshold]; closed when < [closedThreshold].
class BlinkLivenessTracker {
  static const double openThreshold = 0.70;
  static const double closedThreshold = 0.30;

  bool _sawOpen = false;
  bool _sawClosed = false;
  bool _blink = false;

  bool get blinkDetected => _blink;

  void record(double eyeOpenProbability) {
    if (_blink) return;
    if (!_sawOpen) {
      if (eyeOpenProbability > openThreshold) _sawOpen = true;
      return;
    }
    if (!_sawClosed) {
      if (eyeOpenProbability < closedThreshold) _sawClosed = true;
      return;
    }
    if (eyeOpenProbability > openThreshold) _blink = true;
  }

  void reset() {
    _sawOpen = false;
    _sawClosed = false;
    _blink = false;
  }
}

enum GateStage { collecting, awaitingBlink, ready }

class GateResult {
  final GateStage stage;

  /// True only when all gates are satisfied and embedding extraction is allowed.
  final bool passed;
  final String message;
  final FaceValidationResult validation;
  final int validFrames;
  final bool blinkDetected;

  const GateResult({
    required this.stage,
    required this.passed,
    required this.message,
    required this.validation,
    required this.validFrames,
    required this.blinkDetected,
  });
}

/// Composes the per-frame validator with multi-frame stability and blink
/// liveness into a single state machine the camera screen drives per frame.
///
/// Flow: collect [requiredFrames] consecutive valid frames → (optional) blink
/// challenge → ready. Losing the face during the blink challenge resets.
class BiometricGate {
  final FaceValidator _validator;
  final FrameStabilityTracker _stability;
  final BlinkLivenessTracker _blink;
  final bool requireBlink;

  GateStage _stage = GateStage.collecting;

  BiometricGate({
    FaceValidator validator = const FaceValidator(),
    int requiredFrames = 3,
    this.requireBlink = true,
  })  : _validator = validator,
        _stability = FrameStabilityTracker(requiredConsecutive: requiredFrames),
        _blink = BlinkLivenessTracker();

  GateStage get stage => _stage;

  GateResult process(FaceObservation o) {
    final v = _validator.validate(o);

    switch (_stage) {
      case GateStage.collecting:
        _stability.record(v.valid);
        if (_stability.isStable) {
          if (requireBlink) {
            _stage = GateStage.awaitingBlink;
            // Seed the blink tracker's "open" state — the stable frames we just
            // collected had open eyes, so the next closed→open is a full blink.
            _blink.record(o.minEyeOpen);
            return _result(false, kMsgBlink, v, false);
          }
          _stage = GateStage.ready;
          return _result(true, kMsgHold, v, false);
        }
        return _result(false, v.valid ? kMsgHold : v.message, v, false);

      case GateStage.awaitingBlink:
        // The face must remain present & unoccluded during the blink challenge,
        // but closed eyes are expected here (that IS the blink).
        if (!o.faceDetected || !o.allCriticalLandmarksPresent) {
          reset();
          return _result(false, v.message, v, false);
        }
        _blink.record(o.minEyeOpen);
        if (_blink.blinkDetected) {
          _stage = GateStage.ready;
          return _result(true, kMsgHold, v, true);
        }
        return _result(false, kMsgBlink, v, false);

      case GateStage.ready:
        return _result(true, kMsgHold, v, true);
    }
  }

  GateResult _result(
          bool passed, String msg, FaceValidationResult v, bool blink) =>
      GateResult(
        stage: _stage,
        passed: passed,
        message: msg,
        validation: v,
        validFrames: _stability.consecutiveValid,
        blinkDetected: blink || _blink.blinkDetected,
      );

  void reset() {
    _stage = GateStage.collecting;
    _stability.reset();
    _blink.reset();
  }
}
