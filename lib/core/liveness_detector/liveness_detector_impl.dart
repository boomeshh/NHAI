import 'dart:math' as math;
import '../camera_frame.dart';
import 'liveness_detector_interface.dart';

/// Concrete implementation of [LivenessDetectorInterface] using Eye Aspect
/// Ratio (EAR) blink detection.
///
/// ## MediaPipe note
/// MediaPipe Face Mesh is not available as a pure Dart package. In production,
/// landmark extraction would be performed by a platform channel or a native
/// plugin that populates [CameraFrame.landmarks]. For testability, this class
/// exposes two pure-Dart entry points:
///
/// - [computeEar] — takes six 2-D eye landmark points and returns the EAR
///   value. Fully unit-testable with no I/O.
/// - [processEarSequence] — takes a pre-computed list of EAR values (one per
///   frame) and runs the blink-detection state machine. Fully unit-testable.
///
/// [detectLiveness] wires these together: it reads landmark data from each
/// [CameraFrame] (via [_extractEarFromFrame]), computes EAR, and feeds the
/// values into the state machine.
///
/// ## EAR formula
/// ```
/// EAR = (||p2 - p6|| + ||p3 - p5||) / (2 × ||p1 - p4||)
/// ```
/// where p1–p6 are the six 2-D eye landmark coordinates (each a
/// `[x, y]` pair).
///
/// ## Blink detection rule
/// A blink is confirmed when EAR drops **below 0.25** and then recovers
/// **above 0.25** within **400 ms**.
///
/// ## Timeout
/// If no valid blink is detected within **5 seconds**, the method resolves
/// with [LivenessResult.failed].
class LivenessDetectorImpl implements LivenessDetectorInterface {
  /// EAR threshold below which the eye is considered closed.
  static const double earThreshold = 0.25;

  /// Maximum duration (ms) between the eye closing and reopening for a blink
  /// to be considered valid.
  static const int blinkWindowMs = 400;

  /// Total liveness challenge duration before timeout.
  static const Duration challengeTimeout = Duration(seconds: 5);

  // ---------------------------------------------------------------------------
  // Public pure-Dart helpers (exposed for testability)
  // ---------------------------------------------------------------------------

  /// Computes the Eye Aspect Ratio (EAR) from six 2-D landmark points.
  ///
  /// [landmarks] must be a list of exactly 6 points, each represented as a
  /// two-element list `[x, y]`:
  ///   - p1 = landmarks[0] (outer corner)
  ///   - p2 = landmarks[1] (upper-outer)
  ///   - p3 = landmarks[2] (upper-inner)
  ///   - p4 = landmarks[3] (inner corner)
  ///   - p5 = landmarks[4] (lower-inner)
  ///   - p6 = landmarks[5] (lower-outer)
  ///
  /// Formula: `(||p2-p6|| + ||p3-p5||) / (2 × ||p1-p4||)`
  ///
  /// Returns 0.0 if the horizontal distance ||p1-p4|| is zero (degenerate
  /// frame) to avoid division by zero.
  double computeEar(List<List<double>> landmarks) {
    assert(landmarks.length == 6, 'Expected exactly 6 landmark points');
    for (final pt in landmarks) {
      assert(pt.length == 2, 'Each landmark must be a [x, y] pair');
    }

    final p1 = landmarks[0];
    final p2 = landmarks[1];
    final p3 = landmarks[2];
    final p4 = landmarks[3];
    final p5 = landmarks[4];
    final p6 = landmarks[5];

    final vertical1 = _euclidean(p2, p6);
    final vertical2 = _euclidean(p3, p5);
    final horizontal = _euclidean(p1, p4);

    if (horizontal == 0.0) return 0.0;
    return (vertical1 + vertical2) / (2.0 * horizontal);
  }

  /// Runs the blink-detection state machine over a pre-computed sequence of
  /// EAR values.
  ///
  /// [earValues] is a list of EAR readings sampled at uniform intervals of
  /// [frameDurationMs] milliseconds (default: 33 ms ≈ 30 fps).
  ///
  /// [timeout] is the maximum total duration to consider (default:
  /// [challengeTimeout] = 5 s). Frames beyond the timeout are ignored.
  ///
  /// Returns [LivenessResult.confirmed] if a valid blink is found:
  ///   1. EAR drops below [earThreshold] (eye closes).
  ///   2. EAR recovers above [earThreshold] within [blinkWindowMs] ms.
  ///
  /// Returns [LivenessResult.failed] if no valid blink is found within the
  /// timeout.
  LivenessResult processEarSequence(
    List<double> earValues, {
    Duration timeout = challengeTimeout,
    int frameDurationMs = 33,
  }) {
    final int maxFrames = (timeout.inMilliseconds / frameDurationMs).ceil();
    final int frameCount = math.min(earValues.length, maxFrames);

    bool eyeClosed = false;
    int closedAtMs = 0;

    for (int i = 0; i < frameCount; i++) {
      final int currentMs = i * frameDurationMs;
      final double ear = earValues[i];

      if (!eyeClosed) {
        // Waiting for the eye to close.
        if (ear < earThreshold) {
          eyeClosed = true;
          closedAtMs = currentMs;
        }
      } else {
        // Eye is closed — waiting for recovery.
        final int elapsedSinceClose = currentMs - closedAtMs;

        if (ear >= earThreshold) {
          // Eye reopened — check if within the blink window.
          if (elapsedSinceClose <= blinkWindowMs) {
            return LivenessResult.confirmed;
          }
          // Recovery was too slow; reset and look for the next blink.
          eyeClosed = false;
        } else if (elapsedSinceClose > blinkWindowMs) {
          // Eye stayed closed too long — not a valid blink; reset.
          eyeClosed = false;
        }
      }
    }

    return LivenessResult.failed;
  }

  // ---------------------------------------------------------------------------
  // LivenessDetectorInterface
  // ---------------------------------------------------------------------------

  /// Processes [frameStream] to detect a blink using EAR analysis.
  ///
  /// Each [CameraFrame] is expected to carry eye landmark data in its
  /// [CameraFrame.landmarks] field (a `List<List<double>>` of 6 points).
  /// Frames without landmark data are skipped.
  ///
  /// Resolves with [LivenessResult.confirmed] on a valid blink, or
  /// [LivenessResult.failed] after [challengeTimeout] with no valid blink.
  ///
  /// Makes zero network calls.
  @override
  Future<LivenessResult> detectLiveness(Stream<CameraFrame> frameStream) async {
    final List<double> earValues = [];

    await for (final frame in frameStream.timeout(
      challengeTimeout,
      onTimeout: (sink) => sink.close(),
    )) {
      final double? ear = _extractEarFromFrame(frame);
      if (ear == null) continue;

      earValues.add(ear);

      // Check incrementally so we can return early on confirmed blink.
      final result = processEarSequence(
        earValues,
        timeout: challengeTimeout,
      );
      if (result == LivenessResult.confirmed) {
        return LivenessResult.confirmed;
      }
    }

    // Stream ended (timeout or exhausted) — do a final check.
    return processEarSequence(earValues, timeout: challengeTimeout);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Extracts an EAR value from [frame] if landmark data is present.
  ///
  /// Returns `null` if the frame carries no landmark data (e.g., no face
  /// detected in that frame).
  double? _extractEarFromFrame(CameraFrame frame) {
    final landmarks = frame.landmarks;
    if (landmarks == null || landmarks.length < 6) return null;
    return computeEar(landmarks.sublist(0, 6));
  }

  /// Euclidean distance between two 2-D points [a] and [b].
  double _euclidean(List<double> a, List<double> b) {
    final dx = a[0] - b[0];
    final dy = a[1] - b[1];
    return math.sqrt(dx * dx + dy * dy);
  }
}
