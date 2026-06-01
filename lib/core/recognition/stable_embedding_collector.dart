// Collects a minimum number of stable (valid) frames AFTER blink/liveness has
// passed, so their embeddings can be averaged before recognition.
//
// Pure and generic so it is unit-testable without a camera. Replaces the prior
// "buffer cleared by the blink's closed-eye frame" behaviour that left only the
// single reopen frame (the cause of `[Recognition] averaged 1/1`).
class StableEmbeddingCollector<T> {
  /// Minimum number of valid frames to collect before averaging.
  final int target;

  final List<T> _items = [];
  bool _armed = false;

  StableEmbeddingCollector({this.target = 5}) : assert(target >= 1);

  /// Begin collecting. Called once, immediately after the blink gate passes.
  void arm() => _armed = true;

  bool get isArmed => _armed;
  int get count => _items.length;
  bool get isComplete => _items.length >= target;
  List<T> get items => List<T>.unmodifiable(_items);

  /// Offers a frame for collection. Collected only when armed, still incomplete
  /// and [valid] (invalid frames — e.g. a blink, occlusion — are ignored, never
  /// reset the buffer). Returns true if it was collected.
  bool offer(T item, {required bool valid}) {
    if (!_armed || isComplete || !valid) return false;
    _items.add(item);
    return true;
  }

  void reset() {
    _armed = false;
    _items.clear();
  }
}
