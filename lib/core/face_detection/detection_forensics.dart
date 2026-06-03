/// Structured, greppable detection-forensics logging (Phase 1).
///
/// Every log line explains WHY a frame is accepted or rejected. The string
/// builders are pure (no I/O) so they can be unit-tested; the `log*` helpers
/// emit them via [debugPrint]. Tags:
///
///   [Detection] [Landmarks] [Pose] [Blink] [Quality] [Decision]
///   [Stability] [LandmarkAudit] [AlignmentFallback]
///
/// Logging only — no behavioural change to detection, recognition, or liveness.
library;

import 'package:flutter/foundation.dart' show debugPrint;

import 'face_quality.dart';
import 'face_stability_tracker.dart';
import 'landmark_audit.dart';

String _f(double? v, [int p = 1]) => v == null ? 'n/a' : v.toStringAsFixed(p);

/// Pure builders for each forensic log line + thin [debugPrint] emitters.
class DetectionForensics {
  // ── [Detection] ────────────────────────────────────────────────────────────
  static String detection({
    required int faces,
    double? confidence,
    required int boxLeft,
    required int boxTop,
    required int boxWidth,
    required int boxHeight,
    required int rotation,
    required int frameWidth,
    required int frameHeight,
  }) =>
      '[Detection] faces=$faces confidence=${_f(confidence, 2)} '
      'box=${boxWidth}x$boxHeight@($boxLeft,$boxTop) rotation=$rotation '
      'frameSize=${frameWidth}x$frameHeight';

  // ── [Landmarks] ────────────────────────────────────────────────────────────
  static String landmarks({
    List<double>? leftEye,
    List<double>? rightEye,
    List<double>? nose,
    List<double>? mouthLeft,
    List<double>? mouthRight,
  }) {
    String pt(List<double>? p) =>
        p == null ? 'null' : '(${_f(p[0])},${_f(p[1])})';
    return '[Landmarks] leftEye=${pt(leftEye)} rightEye=${pt(rightEye)} '
        'nose=${pt(nose)} mouthLeft=${pt(mouthLeft)} mouthRight=${pt(mouthRight)}';
  }

  // ── [Pose] ─────────────────────────────────────────────────────────────────
  static String pose({double? yaw, double? pitch, double? roll}) =>
      '[Pose] yaw=${_f(yaw)} pitch=${_f(pitch)} roll=${_f(roll)}';

  // ── [Blink] ────────────────────────────────────────────────────────────────
  static String blink({
    double? leftEyeOpen,
    double? rightEyeOpen,
    required bool blinkDetected,
  }) =>
      '[Blink] leftEyeOpen=${_f(leftEyeOpen, 2)} '
      'rightEyeOpen=${_f(rightEyeOpen, 2)} blinkDetected=$blinkDetected';

  // ── [Quality] ──────────────────────────────────────────────────────────────
  static String quality({
    required double brightness,
    required double sharpness,
    required double faceCoverage,
    required bool faceCentered,
    required double score,
  }) =>
      '[Quality] brightness=${_f(brightness)} sharpness=${_f(sharpness)} '
      'faceCoverage=${_f(faceCoverage, 3)} faceCentered=$faceCentered '
      'score=${_f(score)}';

  // ── [Decision] ─────────────────────────────────────────────────────────────
  static String decision({required bool accepted, required String reason}) =>
      '[Decision] accepted=$accepted reason=$reason';

  // ── [Stability] ────────────────────────────────────────────────────────────
  static String stability(StabilityReading r) =>
      '[Stability] stable=${r.stable} movement=${_f(r.movement, 3)} '
      'yawDelta=${_f(r.yawDelta)} pitchDelta=${_f(r.pitchDelta)} '
      'rollDelta=${_f(r.rollDelta)} '
      'stableFrames=${r.stableFrames} unstableFrames=${r.unstableFrames}';

  // ── [LandmarkAudit] ────────────────────────────────────────────────────────
  static String landmarkAudit(LandmarkAuditResult a) =>
      '[LandmarkAudit] leftEye=${a.hasLeftEye} rightEye=${a.hasRightEye} '
      'nose=${a.hasNose} mouthLeft=${a.hasMouthLeft} '
      'mouthRight=${a.hasMouthRight} '
      'missing=[${a.missing.join(",")}] path=${a.path.name}';

  // ── [AlignmentFallback] ────────────────────────────────────────────────────
  static String alignmentFallback(LandmarkAuditResult a) =>
      '[AlignmentFallback] reason=${a.fallbackReason}';

  // ── Composite emitter ───────────────────────────────────────────────────────

  /// Emits the full per-frame forensic block. Call once per processed frame.
  /// [quality] / [stability] / [audit] are optional so the raw detector layer
  /// (which has only box + landmarks + pose) can log its subset while the
  /// validation screen logs the complete picture.
  static void logFrame({
    required int faces,
    double? confidence,
    required int boxLeft,
    required int boxTop,
    required int boxWidth,
    required int boxHeight,
    required int rotation,
    required int frameWidth,
    required int frameHeight,
    List<double>? leftEye,
    List<double>? rightEye,
    List<double>? nose,
    List<double>? mouthLeft,
    List<double>? mouthRight,
    double? yaw,
    double? pitch,
    double? roll,
    double? leftEyeOpen,
    double? rightEyeOpen,
    bool blinkDetected = false,
    FaceQualityScore? quality,
    double? brightness,
    double? sharpness,
    StabilityReading? stability,
    LandmarkAuditResult? audit,
  }) {
    debugPrint(detection(
      faces: faces,
      confidence: confidence,
      boxLeft: boxLeft,
      boxTop: boxTop,
      boxWidth: boxWidth,
      boxHeight: boxHeight,
      rotation: rotation,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
    ));
    debugPrint(landmarks(
      leftEye: leftEye,
      rightEye: rightEye,
      nose: nose,
      mouthLeft: mouthLeft,
      mouthRight: mouthRight,
    ));
    debugPrint(pose(yaw: yaw, pitch: pitch, roll: roll));
    debugPrint(DetectionForensics.blink(
      leftEyeOpen: leftEyeOpen,
      rightEyeOpen: rightEyeOpen,
      blinkDetected: blinkDetected,
    ));
    if (audit != null) {
      debugPrint(landmarkAudit(audit));
      if (audit.isFallback) debugPrint(alignmentFallback(audit));
    }
    if (stability != null) debugPrint(DetectionForensics.stability(stability));
    if (quality != null) {
      debugPrint(DetectionForensics.quality(
        brightness: brightness ?? 0,
        sharpness: sharpness ?? 0,
        faceCoverage: quality.faceCoverage,
        faceCentered: quality.faceCentered,
        score: quality.score,
      ));
      debugPrint(decision(
        accepted: quality.accepted,
        reason: quality.accepted ? 'ok' : quality.rejection.name,
      ));
    }
  }
}
