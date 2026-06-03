import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/recognition/recognition_validator.dart';
import 'package:nhai_auth/models/face_pose.dart';

List<({FacePose? bestPose, double similarity})> _runs(
        List<double> sims, FacePose pose) =>
    [for (final s in sims) (bestPose: pose, similarity: s)];

void main() {
  const v = RecognitionValidator(0.85);

  test('stats: avg/min/max/successRate over 10 attempts', () {
    final r = v.analyze(_runs(
        [0.66, 0.71, 0.68, 0.90, 0.70, 0.67, 0.88, 0.69, 0.72, 0.65],
        FacePose.frontal));
    expect(r.attempts.length, 10);
    expect(r.successRate, closeTo(0.2, 1e-9)); // 0.90 & 0.88 pass
    expect(r.maxSimilarity, 0.90);
    expect(r.minSimilarity, 0.65);
    expect(r.avgSimilarity, closeTo(0.726, 1e-3));
    expect(r.stdDevSimilarity, greaterThan(0)); // dispersed attempts
  });

  test('avg ≥ 0.80 → culprit none (healthy); identical attempts → std 0', () {
    final r = v.analyze(_runs(List.filled(10, 0.91), FacePose.frontal));
    expect(r.culprit, Subsystem.none);
    expect(r.successRate, 1.0);
    expect(r.stdDevSimilarity, closeTo(0, 1e-9));
  });

  test('low avg + frontal best pose + healthy gallery → MODEL', () {
    final r = v.analyze(
      _runs(List.filled(10, 0.68), FacePose.frontal),
      galleryPairs: {'FRONTAL_LEFT': 0.78, 'FRONTAL_RIGHT': 0.80},
    );
    expect(r.culprit, Subsystem.model);
    expect(r.verdict, contains('MODEL'));
  });

  test('degenerate gallery (pair >0.95) → ENROLLMENT GALLERY', () {
    final r = v.analyze(
      _runs(List.filled(10, 0.70), FacePose.frontal),
      galleryPairs: {'FRONTAL_LEFT': 0.98, 'FRONTAL_RIGHT': 0.80},
    );
    expect(r.culprit, Subsystem.enrollmentGallery);
  });

  test('over-divergent template (pair <0.50) → ALIGNMENT', () {
    final r = v.analyze(
      _runs(List.filled(10, 0.70), FacePose.frontal),
      galleryPairs: {'FRONTAL_LEFT': 0.42, 'FRONTAL_RIGHT': 0.80},
    );
    expect(r.culprit, Subsystem.alignment);
  });

  test('low avg + non-frontal best pose dominating → ALIGNMENT', () {
    final r = v.analyze(_runs(List.filled(10, 0.70), FacePose.left));
    expect(r.culprit, Subsystem.alignment);
  });

  test('CSV contains rows, metrics, gallery pairs and culprit', () {
    final r = v.analyze(
      _runs(List.filled(3, 0.68), FacePose.frontal),
      galleryPairs: {'FRONTAL_LEFT': 0.80},
    );
    final csv = r.toCsv();
    expect(csv, contains('attempt,bestPose,similarity,result'));
    expect(csv, contains('1,FRONTAL,0.6800,FAIL'));
    expect(csv, contains('averageSimilarity,'));
    expect(csv, contains('gallery_frontal_left,0.8000'));
    expect(csv, contains('culprit,model'));
  });
}
