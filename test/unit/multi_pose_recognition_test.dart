import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/auth_engine/auth_engine_impl.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_impl.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_interface.dart';
import 'package:nhai_auth/core/liveness_detector/liveness_detector_interface.dart';
import 'package:nhai_auth/core/recognition/embedding_math.dart';
import 'package:nhai_auth/core/recognition/five_point_aligner.dart';
import 'package:nhai_auth/core/recognition/gallery_matcher.dart';
import 'package:nhai_auth/core/recognition/multi_pose_enrollment_controller.dart';
import 'package:nhai_auth/core/recognition/pose_classifier.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/face_pose.dart';
import 'package:nhai_auth/models/face_template.dart';

// ── shared stubs ──────────────────────────────────────────────────────────
class _Storage implements StorageManagerInterface {
  final Map<String, EmployeeRecord> e = {};
  @override
  Future<void> saveEmployeeRecord(EmployeeRecord r) async => e[r.employeeId] = r;
  @override
  Future<EmployeeRecord?> getEmployeeRecord(String id) async => e[id];
  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async => e.values.toList();
  @override
  Future<bool> employeeExists(String id) async => e.containsKey(id);
  @override
  Future<void> deleteEmployeeRecord(String id) async => e.remove(id);
  @override
  Future<void> logAuthAttempt(AuthLogEntry x) async {}
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

// Returns a distinct embedding per frame (keyed by first byte) for enrollment.
class _SeedEngine extends AuthEngineImpl {
  _SeedEngine(StorageManagerInterface s)
      : super(storage: s, livenessDetector: _Liveness(), livenessEnabled: false);
  @override
  Future<FaceEmbedding> runInference(CameraFrame f) async =>
      FaceEmbedding(_vec(f.bytes.first.toDouble()));
}

// Returns a fixed live embedding regardless of frame (for matcher tests).
class _FixedLiveEngine extends AuthEngineImpl {
  final List<double> live;
  _FixedLiveEngine(StorageManagerInterface s, this.live)
      : super(storage: s, livenessDetector: _Liveness(), livenessEnabled: false);
  @override
  Future<FaceEmbedding> runInference(CameraFrame f) async => FaceEmbedding(live);
}

List<double> _vec(double seed) =>
    EmbeddingMath.l2Normalize(List<double>.generate(192, (i) => (i + seed) % 11 - 5.0));

CameraFrame _frame([int seed = 1]) =>
    CameraFrame(bytes: [seed], width: 112, height: 112, sharpnessScore: 50.0);

FaceTemplate _tpl(FacePose pose, double seed) => FaceTemplate(
      embedding: FaceEmbedding(_vec(seed)),
      poseLabel: pose,
      yaw: 0,
      pitch: 0,
      qualityScore: 1.0,
      createdAt: DateTime.utc(2026, 1, 1),
      pipelineVersion: 3,
    );

void main() {
  // ── Phase 1: pose classifier ──────────────────────────────────────────────
  group('PoseClassifier', () {
    test('classifies each target pose', () {
      expect(PoseClassifier.matches(FacePose.frontal, 0, 0), isTrue);
      expect(PoseClassifier.matches(FacePose.left, -20, 0), isTrue);
      expect(PoseClassifier.matches(FacePose.right, 20, 0), isTrue);
      expect(PoseClassifier.matches(FacePose.up, 0, 15), isTrue);
      expect(PoseClassifier.matches(FacePose.down, 0, -15), isTrue);
    });
    test('frontal rejects turned heads; left rejects frontal', () {
      expect(PoseClassifier.matches(FacePose.frontal, 25, 0), isFalse);
      expect(PoseClassifier.matches(FacePose.left, 0, 0), isFalse);
      expect(PoseClassifier.classify(20, 0), FacePose.right);
      expect(PoseClassifier.enrollmentSequence.length, 5);
    });
  });

  // ── Phase 2: gallery matcher + Phase 4 backward compat ─────────────────────
  group('GalleryMatcher', () {
    test('multi-template gallery returns MAX similarity and best pose', () {
      final live = _vec(3); // identical to the RIGHT template
      final rec = EmployeeRecord(
        employeeId: 'E',
        name: 'E',
        department: 'D',
        embedding: FaceEmbedding(_vec(1)),
        enrolledAt: DateTime.utc(2026, 1, 1),
        templates: [
          _tpl(FacePose.frontal, 1),
          _tpl(FacePose.left, 2),
          _tpl(FacePose.right, 3),
          _tpl(FacePose.up, 4),
          _tpl(FacePose.down, 5),
        ],
      );
      final m = GalleryMatcher.matchEmployee(live, rec);
      expect(m.templateCount, 5);
      expect(m.bestPose, FacePose.right);
      expect(m.score, closeTo(1.0, 1e-9));
    });

    test('legacy single-template record still matches (backward compat)', () {
      final live = _vec(7);
      final rec = EmployeeRecord(
        employeeId: 'OLD',
        name: 'O',
        department: 'D',
        embedding: FaceEmbedding(_vec(7)),
        enrolledAt: DateTime.utc(2026, 1, 1),
      ); // templates == null
      final m = GalleryMatcher.matchEmployee(live, rec);
      expect(m.templateCount, 1);
      expect(m.bestPose, isNull);
      expect(m.score, closeTo(1.0, 1e-9));
    });

    test('length mismatch → no match', () {
      final m = GalleryMatcher.matchEmployee(
        List<double>.filled(128, 0.1),
        EmployeeRecord(
          employeeId: 'X',
          name: 'X',
          department: 'D',
          embedding: FaceEmbedding(_vec(1)),
          enrolledAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(m.templateCount, 0);
      expect(m.score, 0.0);
    });
  });

  // ── Phase 3: 5-point aligner ───────────────────────────────────────────────
  group('FivePointAligner', () {
    test('solve recovers an exact affine mapping src → canonical', () {
      // Build src by applying a known affine to the canonical points.
      const A = Affine(1.5, 0.2, -0.1, 1.3, 12.0, -8.0);
      final src = FivePointAligner.canonical112.map(A.apply).toList();
      final back = FivePointAligner.solve(src, FivePointAligner.canonical112)!;
      for (var i = 0; i < 5; i++) {
        final mapped = back.apply(src[i]);
        expect(mapped[0], closeTo(FivePointAligner.canonical112[i][0], 1e-3));
        expect(mapped[1], closeTo(FivePointAligner.canonical112[i][1], 1e-3));
      }
    });

    test('align returns 112×112×3 normalized to [-1,1]', () {
      final rgb = List<int>.generate(200 * 200 * 3, (i) => i % 256);
      final out = FivePointAligner.align(rgb, 200, 200, const [
        [70, 90], [120, 90], [95, 115], [75, 140], [115, 140]
      ], 112);
      expect(out, isNotNull);
      expect(out!.length, 112);
      expect(out[0][0].length, 3);
      for (final row in out) {
        for (final px in row) {
          for (final c in px) {
            expect(c, inInclusiveRange(-1.0, 1.0));
          }
        }
      }
    });

    test('degenerate (collinear) landmarks → null', () {
      final src = List.generate(5, (i) => [i.toDouble(), 0.0]); // all on a line
      expect(FivePointAligner.solve(src, FivePointAligner.canonical112), isNull);
    });
  });

  // ── Phase 1: multi-pose enrollment controller ──────────────────────────────
  group('MultiPoseEnrollmentController', () {
    test('walks the 5-pose sequence, collecting per target pose', () {
      final c = MultiPoseEnrollmentController(framesPerPose: 2);
      // Wrong-pose / invalid frames are ignored.
      expect(c.offer(_frame(), yaw: 30, pitch: 0, valid: true), isFalse);
      expect(c.offer(_frame(), yaw: 0, pitch: 0, valid: false), isFalse);
      // angles for the ordered sequence frontal,left,right,up,down
      final seq = [
        [0.0, 0.0], [-20.0, 0.0], [20.0, 0.0], [0.0, 15.0], [0.0, -15.0]
      ];
      for (final a in seq) {
        expect(c.offer(_frame(), yaw: a[0], pitch: a[1], valid: true), isTrue);
        expect(c.offer(_frame(), yaw: a[0], pitch: a[1], valid: true), isTrue);
      }
      expect(c.isComplete, isTrue);
      expect(c.buckets.keys.toSet(), FacePose.values.toSet());
      expect(c.buckets[FacePose.frontal]!.length, 2);
    });
  });

  // ── Phase 1: FaceTemplate / EmployeeRecord serialization ───────────────────
  group('serialization', () {
    test('FaceTemplate round-trips', () {
      final t = _tpl(FacePose.left, 2);
      final r = FaceTemplate.fromJson(t.toJson());
      expect(r.poseLabel, FacePose.left);
      expect(r.pipelineVersion, 3);
      expect(r.embedding.vector.length, 192);
    });

    test('EmployeeRecord with gallery round-trips; legacy omits templates key',
        () {
      final withGallery = EmployeeRecord(
        employeeId: 'G',
        name: 'G',
        department: 'D',
        embedding: FaceEmbedding(_vec(1)),
        enrolledAt: DateTime.utc(2026, 1, 1),
        templates: [_tpl(FacePose.frontal, 1), _tpl(FacePose.left, 2)],
      );
      final back = EmployeeRecord.fromJson(withGallery.toJson());
      expect(back.hasGallery, isTrue);
      expect(back.templates!.length, 2);

      final legacy = EmployeeRecord(
        employeeId: 'L',
        name: 'L',
        department: 'D',
        embedding: FaceEmbedding(_vec(1)),
        enrolledAt: DateTime.utc(2026, 1, 1),
      );
      expect(legacy.toJson().containsKey('templates'), isFalse);
      expect(EmployeeRecord.fromJson(legacy.toJson()).hasGallery, isFalse);
    });
  });

  // ── Phase 1: enrollMultiPose builds a gallery ──────────────────────────────
  group('EnrollmentModuleImpl.enrollMultiPose', () {
    test('stores one template per captured pose + frontal backward-compat', () async {
      final storage = _Storage();
      final module =
          EnrollmentModuleImpl(authEngine: _SeedEngine(storage), storage: storage);
      final posed = <FacePose, List<CameraFrame>>{
        FacePose.frontal: [_frame(1), _frame(1)],
        FacePose.left: [_frame(2)],
        FacePose.right: [_frame(3)],
        FacePose.up: [_frame(4)],
        FacePose.down: [_frame(5)],
      };
      final r = await module.enrollMultiPose(
        const EmployeeFormData(employeeId: 'EMP1', name: 'A', department: 'D'),
        posed,
      );
      expect(r.success, isTrue);
      expect(r.record!.hasGallery, isTrue);
      expect(r.record!.templates!.length, 5);
      // Frontal template's embedding is mirrored into the legacy field.
      final frontal = r.record!.templates!
          .firstWhere((t) => t.poseLabel == FacePose.frontal);
      expect(r.record!.embedding.vector, equals(frontal.embedding.vector));
      // Persisted to storage.
      expect((await storage.getEmployeeRecord('EMP1'))!.hasGallery, isTrue);
    });

    test('rejects when no usable frames captured', () async {
      final storage = _Storage();
      final module =
          EnrollmentModuleImpl(authEngine: _SeedEngine(storage), storage: storage);
      final r = await module.enrollMultiPose(
        const EmployeeFormData(employeeId: 'EMP2', name: 'B', department: 'D'),
        const {},
      );
      expect(r.success, isFalse);
    });
  });

  // ── Phase 2/4: engine authenticates via gallery + legacy ───────────────────
  group('AuthEngine gallery matching', () {
    test('multi-template employee verifies against best pose', () async {
      final live = _vec(3);
      final storage = _Storage();
      storage.e['E'] = EmployeeRecord(
        employeeId: 'E',
        name: 'E',
        department: 'D',
        embedding: FaceEmbedding(_vec(1)),
        enrolledAt: DateTime.utc(2026, 1, 1),
        templates: [
          _tpl(FacePose.frontal, 1),
          _tpl(FacePose.left, 2),
          _tpl(FacePose.right, 3), // == live
          _tpl(FacePose.up, 4),
          _tpl(FacePose.down, 5),
        ],
      );
      final engine = _FixedLiveEngine(storage, live);
      final res = await engine.authenticate(_frame());
      expect(res.classification, AuthClassification.verified);
      expect(res.matchedEmployeeId, 'E');
      expect(res.trustScore, closeTo(1.0, 1e-6));
    });

    test('legacy single-template employee still verifies (backward compat)',
        () async {
      final live = _vec(9);
      final storage = _Storage();
      storage.e['OLD'] = EmployeeRecord(
        employeeId: 'OLD',
        name: 'O',
        department: 'D',
        embedding: FaceEmbedding(_vec(9)),
        enrolledAt: DateTime.utc(2026, 1, 1),
      );
      final engine = _FixedLiveEngine(storage, live);
      final res = await engine.authenticate(_frame());
      expect(res.classification, AuthClassification.verified);
      expect(res.matchedEmployeeId, 'OLD');
    });
  });
}
