// Feature: nhai-offline-auth, Property 3: Best frame selection is a maximum
//
// **Validates: Requirements 4.4**
//
// Property: For any non-empty list of camera frames with associated sharpness
// scores, `selectBestFrame` returns the frame with the strictly highest
// sharpness score.
//
// Minimum 100 iterations.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_impl.dart';

// ---------------------------------------------------------------------------
// Generator helpers
// ---------------------------------------------------------------------------

/// Generates a [CameraFrame] with the given [sharpnessScore].
CameraFrame _frameWithSharpness(double sharpnessScore) {
  return CameraFrame(
    bytes: const [0],
    width: 1,
    height: 1,
    sharpnessScore: sharpnessScore,
  );
}

/// Generates a non-empty list of [CameraFrame] objects with random sharpness
/// scores using [rng].
///
/// List length is between 1 and [maxLength] (inclusive).
/// Sharpness scores are drawn from the full double range [0.0, 1000.0].
List<CameraFrame> _generateFrameList(Random rng, {int maxLength = 20}) {
  final count = 1 + rng.nextInt(maxLength);
  return List.generate(
    count,
    (_) => _frameWithSharpness(rng.nextDouble() * 1000.0),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Property 3: Best frame selection is a maximum', () {
    late EnrollmentModuleImpl module;

    setUp(() {
      // No auth engine or storage needed — selectBestFrame is pure.
      module = EnrollmentModuleImpl();
    });

    // -----------------------------------------------------------------------
    // Core property: selectBestFrame returns the frame with the maximum
    // sharpness score for 100 randomly generated non-empty frame lists.
    // -----------------------------------------------------------------------

    test(
        'property: selectBestFrame always returns the frame with the maximum '
        'sharpness score for 100 randomly generated non-empty lists', () {
      final rng = Random(42);

      for (int i = 0; i < 100; i++) {
        final frames = _generateFrameList(rng);

        final best = module.selectBestFrame(frames);

        // Compute the expected maximum sharpness score.
        final maxSharpness = frames
            .map((f) => f.sharpnessScore)
            .reduce((a, b) => a > b ? a : b);

        expect(
          best.sharpnessScore,
          equals(maxSharpness),
          reason:
              'Iteration $i: selectBestFrame returned a frame with sharpness '
              '${best.sharpnessScore} but the maximum in the list was '
              '$maxSharpness (list length=${frames.length})',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Property: no frame in the list has a higher sharpness than the result.
    // This is the "is a maximum" invariant stated directly.
    // -----------------------------------------------------------------------

    test(
        'property: no frame in the list has a higher sharpness score than '
        'the selected frame (100 iterations)', () {
      final rng = Random(7);

      for (int i = 0; i < 100; i++) {
        final frames = _generateFrameList(rng);
        final best = module.selectBestFrame(frames);

        for (int j = 0; j < frames.length; j++) {
          expect(
            frames[j].sharpnessScore <= best.sharpnessScore,
            isTrue,
            reason:
                'Iteration $i, frame $j: sharpness ${frames[j].sharpnessScore} '
                'exceeds the selected frame sharpness ${best.sharpnessScore}',
          );
        }
      }
    });

    // -----------------------------------------------------------------------
    // Property: the returned frame is actually a member of the input list.
    // -----------------------------------------------------------------------

    test(
        'property: selectBestFrame always returns a frame that is in the '
        'input list (100 iterations)', () {
      final rng = Random(13);

      for (int i = 0; i < 100; i++) {
        final frames = _generateFrameList(rng);
        final best = module.selectBestFrame(frames);

        expect(
          frames.contains(best),
          isTrue,
          reason:
              'Iteration $i: the returned frame is not a member of the '
              'input list',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Boundary: single-element list — the only frame must be returned.
    // -----------------------------------------------------------------------

    test('single-element list always returns the only frame', () {
      final rng = Random(99);

      for (int i = 0; i < 100; i++) {
        final sharpness = rng.nextDouble() * 1000.0;
        final frame = _frameWithSharpness(sharpness);
        final result = module.selectBestFrame([frame]);

        expect(
          result,
          same(frame),
          reason:
              'Iteration $i: single-element list should return the only frame '
              '(sharpness=$sharpness)',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Boundary: two-element list — the sharper frame must be returned.
    // -----------------------------------------------------------------------

    test(
        'two-element list: the frame with the higher sharpness score is '
        'always returned (100 iterations)', () {
      final rng = Random(31);

      for (int i = 0; i < 100; i++) {
        // Ensure the two scores are distinct.
        double a = rng.nextDouble() * 500.0;
        double b = rng.nextDouble() * 500.0 + 500.0; // b is always > 500 > a

        final frameA = _frameWithSharpness(a);
        final frameB = _frameWithSharpness(b);

        // Test both orderings.
        expect(
          module.selectBestFrame([frameA, frameB]),
          same(frameB),
          reason:
              'Iteration $i [A,B]: expected frameB (sharpness=$b) but got '
              'a frame with sharpness=${module.selectBestFrame([frameA, frameB]).sharpnessScore}',
        );
        expect(
          module.selectBestFrame([frameB, frameA]),
          same(frameB),
          reason:
              'Iteration $i [B,A]: expected frameB (sharpness=$b) but got '
              'a frame with sharpness=${module.selectBestFrame([frameB, frameA]).sharpnessScore}',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Boundary: all frames have the same sharpness — any frame is valid,
    // but the result must still be a member of the list.
    // -----------------------------------------------------------------------

    test(
        'all frames with equal sharpness: result is still a member of the '
        'list (100 iterations)', () {
      final rng = Random(55);

      for (int i = 0; i < 100; i++) {
        final sharpness = rng.nextDouble() * 1000.0;
        final count = 1 + rng.nextInt(10);
        final frames =
            List.generate(count, (_) => _frameWithSharpness(sharpness));

        final best = module.selectBestFrame(frames);

        expect(
          frames.contains(best),
          isTrue,
          reason:
              'Iteration $i: result is not a member of the list when all '
              'frames share sharpness=$sharpness',
        );
        expect(
          best.sharpnessScore,
          equals(sharpness),
          reason:
              'Iteration $i: result sharpness ${best.sharpnessScore} != '
              'expected $sharpness',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Boundary: large list (100 frames) — maximum is still found correctly.
    // -----------------------------------------------------------------------

    test('large list of 100 frames: maximum sharpness frame is returned', () {
      final rng = Random(77);
      final frames = List.generate(
        100,
        (_) => _frameWithSharpness(rng.nextDouble() * 1000.0),
      );

      // Inject a known maximum at a random position.
      final maxIndex = rng.nextInt(100);
      final maxFrame = _frameWithSharpness(9999.0);
      frames[maxIndex] = maxFrame;

      final best = module.selectBestFrame(frames);

      expect(
        best,
        same(maxFrame),
        reason:
            'Expected the injected maximum frame (sharpness=9999.0) at index '
            '$maxIndex to be selected',
      );
    });

    // -----------------------------------------------------------------------
    // Boundary: empty list throws ArgumentError.
    // -----------------------------------------------------------------------

    test('empty list throws ArgumentError', () {
      expect(
        () => module.selectBestFrame([]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
