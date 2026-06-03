import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/face_detection/landmark_audit.dart';

void main() {
  const auditor = LandmarkAuditor();

  LandmarkAuditResult audit({
    bool le = true,
    bool re = true,
    bool nose = true,
    bool ml = true,
    bool mr = true,
  }) =>
      auditor.audit(
        hasLeftEye: le,
        hasRightEye: re,
        hasNose: nose,
        hasMouthLeft: ml,
        hasMouthRight: mr,
      );

  group('LandmarkAuditor', () {
    test('all five present → 5-point, no fallback', () {
      final r = audit();
      expect(r.path, AlignmentPath.fivePoint);
      expect(r.hasFivePoint, isTrue);
      expect(r.isFallback, isFalse);
      expect(r.missing, isEmpty);
      expect(r.fallbackReason, isEmpty);
    });

    test('eyes only → 2-point fallback naming the missing landmarks', () {
      final r = audit(nose: false, ml: false, mr: false);
      expect(r.path, AlignmentPath.twoPoint);
      expect(r.isFallback, isTrue);
      expect(r.missing, containsAll(['nose', 'mouthLeft', 'mouthRight']));
      expect(r.fallbackReason, contains('2-point'));
    });

    test('a missing eye → square-crop fallback', () {
      final r = audit(le: false);
      expect(r.path, AlignmentPath.square);
      expect(r.missing, contains('leftEye'));
      expect(r.fallbackReason, contains('square'));
    });

    test('no landmarks at all → square', () {
      final r = audit(le: false, re: false, nose: false, ml: false, mr: false);
      expect(r.path, AlignmentPath.square);
      expect(r.missing, hasLength(5));
    });

    test('missing only nose → 2-point (eyes still present)', () {
      final r = audit(nose: false);
      expect(r.path, AlignmentPath.twoPoint);
      expect(r.missing, ['nose']);
    });
  });
}
