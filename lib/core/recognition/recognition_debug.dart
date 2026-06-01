// TEMPORARY experiment harness flag. Forces a single preprocessing/alignment
// path so Experiments A/B/C can be compared with everything else held constant
// (threshold, matcher, gallery, blink, averaging are NOT affected).
//
// Default is [AlignmentMode.auto] → production behaviour unchanged.
enum AlignmentMode {
  /// Production precedence: 5-point → 2-point → square.
  auto,

  /// Experiment C: force 5-point affine alignment.
  fivePoint,

  /// Experiment A: force 2-point eye alignment only.
  twoPoint,

  /// Experiment B: force square crop only.
  square,
}

class RecognitionDebugMode {
  /// When not [AlignmentMode.auto], the model runner uses exactly this path.
  static AlignmentMode forcedAlignment = AlignmentMode.auto;

  static bool get enabled => forcedAlignment != AlignmentMode.auto;

  static void reset() => forcedAlignment = AlignmentMode.auto;
}
