// Deterministic, injectable ID generator (avoids Date.now/random for testable,
// reproducible IDs). Production may inject a UUID-backed implementation.
class IdGenerator {
  int _counter = 0;
  final String _seed;

  IdGenerator([this._seed = 'NHAI']);

  String next(String prefix) {
    _counter++;
    return '$prefix-$_seed-${_counter.toString().padLeft(6, '0')}';
  }
}
