import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/recognition/enrollment_pose_audit.dart';
import 'package:nhai_auth/models/face_pose.dart';

PoseSample _s(FacePose label, double yaw, double pitch,
        {double quality = 1.0, double magnitude = 1.0}) =>
    PoseSample(
        assignedLabel: label,
        measuredYaw: yaw,
        measuredPitch: pitch,
        quality: quality,
        magnitude: magnitude);

void main() {
  group('EnrollmentPoseAuditor', () {
    test('well-captured gallery: labels match, frontal centred', () {
      final r = EnrollmentPoseAuditor.audit([
        _s(FacePose.frontal, 1, 2),
        _s(FacePose.left, -20, 0),
        _s(FacePose.right, 20, 0),
        _s(FacePose.up, 0, 15),
        _s(FacePose.down, 0, -15),
      ]);
      expect(r.mislabeled, isEmpty);
      expect(r.anyFrontalOffCentre, isFalse);
      expect(r.pitchAxisMirrored, isFalse);
      expect(r.yawAxisMirrored, isFalse);
    });

    test('FRONTAL captured off-centre is flagged', () {
      final r = EnrollmentPoseAuditor.audit([
        _s(FacePose.frontal, 2, 13), // pitch beyond ±10 frontal tolerance
      ]);
      expect(r.anyFrontalOffCentre, isTrue);
      // 2°/13° classifies as UP, so the FRONTAL label does not match.
      expect(r.mislabeled.map((e) => e.assignedLabel), contains(FacePose.frontal));
    });

    test('measured angle drives the expected label', () {
      final r = EnrollmentPoseAuditor.audit([_s(FacePose.frontal, 2, 13)]);
      expect(r.entries.single.expectedLabel, FacePose.up);
      expect(r.entries.single.labelMatches, isFalse);
    });

    test('mirrored pitch axis detected (up/down captured with wrong sign)', () {
      final r = EnrollmentPoseAuditor.audit([
        _s(FacePose.up, 0, -15), // UP label but negative pitch
        _s(FacePose.down, 0, 15), // DOWN label but positive pitch
      ]);
      expect(r.pitchAxisMirrored, isTrue);
    });

    test('mirrored yaw axis detected (left/right swapped sign)', () {
      final r = EnrollmentPoseAuditor.audit([
        _s(FacePose.left, 20, 0),
        _s(FacePose.right, -20, 0),
      ]);
      expect(r.yawAxisMirrored, isTrue);
    });

    test('toLog emits per-pose lines + summary', () {
      final log = EnrollmentPoseAuditor.audit([_s(FacePose.frontal, 1, 1)]).toLog();
      expect(log, contains('[EnrollmentPoseAudit] pose=FRONTAL'));
      expect(log, contains('measuredPitch=1.0'));
      expect(log, contains('labelMatches=true'));
      expect(log, contains('frontalOffCentre=false'));
    });
  });
}
