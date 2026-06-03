// Enrollment pose-quality audit (diagnostics only).
//
// For each captured pose this records the MEASURED head angles, the pose label
// that was assigned, the label that the angles actually imply, the template
// quality and the embedding magnitude. It surfaces three enrollment defects the
// stored gallery cannot reveal on its own (the gallery stores only NOMINAL
// angles): a FRONTAL template captured off-centre, a mislabeled pose, and a
// mirrored/swapped yaw or pitch axis.
//
// PURE and read-only — it does not touch the matcher, threshold, recognition
// engine, model, or the enrollment decision.
library;

import '../../models/face_pose.dart';
import 'pose_classifier.dart';

/// Raw per-pose measurement gathered during enrollment.
class PoseSample {
  final FacePose assignedLabel;
  final double measuredYaw;
  final double measuredPitch;
  final double quality;
  final double magnitude;

  const PoseSample({
    required this.assignedLabel,
    required this.measuredYaw,
    required this.measuredPitch,
    required this.quality,
    required this.magnitude,
  });
}

/// Audited entry for one pose template.
class PoseAuditEntry {
  final FacePose assignedLabel;
  final double measuredYaw;
  final double measuredPitch;
  final double quality;
  final double magnitude;

  /// The label the MEASURED angles imply via [PoseClassifier]; null if the
  /// angles fall in no pose window.
  final FacePose? expectedLabel;

  const PoseAuditEntry({
    required this.assignedLabel,
    required this.measuredYaw,
    required this.measuredPitch,
    required this.quality,
    required this.magnitude,
    required this.expectedLabel,
  });

  /// The assigned label agrees with what the angles imply.
  bool get labelMatches => expectedLabel == assignedLabel;

  /// FRONTAL was assigned but the head was not actually frontal (either axis
  /// beyond the frontal tolerance) — a FRONTAL template captured off-centre.
  bool get frontalOffCentre =>
      assignedLabel == FacePose.frontal &&
      (measuredYaw.abs() >= PoseClassifier.frontalTolerance ||
          measuredPitch.abs() >= PoseClassifier.frontalTolerance);

  /// The pitch sign contradicts the label's nominal direction (up ⇒ +pitch,
  /// down ⇒ −pitch). A consistent contradiction across up/down ⇒ mirrored axis.
  bool get pitchSignContradicts =>
      (assignedLabel == FacePose.up && measuredPitch < 0) ||
      (assignedLabel == FacePose.down && measuredPitch > 0);

  /// The yaw sign contradicts the label's nominal direction (left ⇒ −yaw,
  /// right ⇒ +yaw).
  bool get yawSignContradicts =>
      (assignedLabel == FacePose.left && measuredYaw > 0) ||
      (assignedLabel == FacePose.right && measuredYaw < 0);
}

class EnrollmentPoseAuditReport {
  final List<PoseAuditEntry> entries;
  const EnrollmentPoseAuditReport(this.entries);

  List<PoseAuditEntry> get mislabeled =>
      entries.where((e) => !e.labelMatches).toList();

  bool get anyFrontalOffCentre => entries.any((e) => e.frontalOffCentre);

  /// Suspected mirror on the pitch (up/down) axis: every up/down template's
  /// measured pitch sign contradicts its label.
  bool get pitchAxisMirrored {
    final ud = entries
        .where((e) => e.assignedLabel == FacePose.up || e.assignedLabel == FacePose.down)
        .toList();
    return ud.isNotEmpty && ud.every((e) => e.pitchSignContradicts);
  }

  /// Suspected mirror on the yaw (left/right) axis.
  bool get yawAxisMirrored {
    final lr = entries
        .where((e) => e.assignedLabel == FacePose.left || e.assignedLabel == FacePose.right)
        .toList();
    return lr.isNotEmpty && lr.every((e) => e.yawSignContradicts);
  }

  String toLog() {
    final b = StringBuffer();
    for (final e in entries) {
      b.writeln('[EnrollmentPoseAudit] pose=${e.assignedLabel.label} '
          'measuredYaw=${e.measuredYaw.toStringAsFixed(1)} '
          'measuredPitch=${e.measuredPitch.toStringAsFixed(1)} '
          'expected=${e.expectedLabel?.label ?? "NONE"} '
          'labelMatches=${e.labelMatches} '
          'quality=${e.quality.toStringAsFixed(2)} '
          'magnitude=${e.magnitude.toStringAsFixed(4)}'
          '${e.frontalOffCentre ? " FLAG=frontalOffCentre" : ""}');
    }
    b.write('[EnrollmentPoseAudit] mislabeled=${mislabeled.map((e) => e.assignedLabel.label).toList()} '
        'frontalOffCentre=$anyFrontalOffCentre '
        'pitchAxisMirrored=$pitchAxisMirrored yawAxisMirrored=$yawAxisMirrored');
    return b.toString();
  }
}

class EnrollmentPoseAuditor {
  const EnrollmentPoseAuditor();

  static EnrollmentPoseAuditReport audit(List<PoseSample> samples) {
    return EnrollmentPoseAuditReport([
      for (final s in samples)
        PoseAuditEntry(
          assignedLabel: s.assignedLabel,
          measuredYaw: s.measuredYaw,
          measuredPitch: s.measuredPitch,
          quality: s.quality,
          magnitude: s.magnitude,
          expectedLabel:
              PoseClassifier.classify(s.measuredYaw, s.measuredPitch),
        ),
    ]);
  }
}
