import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/recognition/recognition_debug.dart';
import 'package:nhai_auth/core/recognition/recognition_experiment.dart';

void main() {
  setUp(RecognitionDebugMode.reset);
  tearDown(RecognitionDebugMode.reset);

  group('VerifyStats.from', () {
    test('computes avg/min/max/successRate against threshold', () {
      final s = VerifyStats.from([0.70, 0.80, 0.90, 0.86], 0.85);
      expect(s.count, 4);
      expect(s.avg, closeTo(0.815, 1e-9));
      expect(s.min, 0.70);
      expect(s.max, 0.90);
      expect(s.successRate, closeTo(0.5, 1e-9)); // 0.90 & 0.86 pass
    });

    test('empty → zeros', () {
      final s = VerifyStats.from(const [], 0.85);
      expect(s.count, 0);
      expect(s.successRate, 0);
    });
  });

  group('RecognitionExperiment', () {
    test('runMode forces the alignment mode during the run and resets after',
        () async {
      AlignmentMode? duringEnroll;
      final exp = RecognitionExperiment(
        freshEnroll: () async {
          duringEnroll = RecognitionDebugMode.forcedAlignment;
        },
        verifyOnce: () async => 0.9,
        threshold: 0.85,
      );
      await exp.runMode(AlignmentMode.twoPoint, verifications: 3);
      expect(duringEnroll, AlignmentMode.twoPoint); // forced during the run
      expect(RecognitionDebugMode.forcedAlignment, AlignmentMode.auto); // reset
    });

    test('runAll over A/B/C identifies the highest-avg mode', () async {
      // Fake: each mode yields a fixed genuine score (square wins here).
      final scoreByMode = {
        AlignmentMode.twoPoint: 0.82,
        AlignmentMode.square: 0.91,
        AlignmentMode.fivePoint: 0.67,
      };
      final exp = RecognitionExperiment(
        freshEnroll: () async {},
        verifyOnce: () async =>
            scoreByMode[RecognitionDebugMode.forcedAlignment]!,
        threshold: 0.85,
      );
      final rows = await exp.runAll(verifications: 10);
      expect(rows.length, 3);
      expect(RecognitionExperiment.bestMode(rows), AlignmentMode.square);

      final fiveP = rows.firstWhere((r) => r.mode == AlignmentMode.fivePoint);
      expect(fiveP.stats.avg, closeTo(0.67, 1e-9));
      expect(fiveP.stats.successRate, 0.0); // 0.67 < 0.85 → all fail
      final sq = rows.firstWhere((r) => r.mode == AlignmentMode.square);
      expect(sq.stats.successRate, 1.0); // 0.91 ≥ 0.85 → all pass

      // Threshold is only read for reporting, never mutated.
      expect(exp.threshold, 0.85);
    });
  });
}
