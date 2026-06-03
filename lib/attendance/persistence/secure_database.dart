// Persistence port for the NHAI attendance platform.
//
// A narrow key/value-per-table abstraction the repositories are written
// against. Two implementations exist:
//
//   * [InMemorySecureDatabase]  — pure Dart; used by all tests and as a safe
//     fallback when the native database is unavailable.
//   * SqlCipherDatabase (see sqlcipher_database.dart) — an AES-256 encrypted
//     SQLite database via SQLCipher, used on-device.
//
// Repositories depend only on this interface, so the same daily/monthly
// summary, sync-queue and dashboard logic runs identically over either backend
// and is fully unit-testable without the native plugin.
library;

/// A row is an entity's JSON map, addressed by (table, id).
abstract class SecureDatabase {
  /// Opens / creates the database and its tables. Idempotent.
  Future<void> init();

  /// Inserts or replaces the row [id] in [table].
  Future<void> put(String table, String id, Map<String, dynamic> json);

  /// Returns the row [id] from [table], or null.
  Future<Map<String, dynamic>?> get(String table, String id);

  /// Returns every row in [table].
  Future<List<Map<String, dynamic>>> getAll(String table);

  /// Deletes row [id] from [table] (no-op if absent).
  Future<void> delete(String table, String id);

  /// Deletes all rows whose id is in [ids] from [table]. Returns the count
  /// actually removed.
  Future<int> deleteWhereIdIn(String table, Iterable<String> ids);

  /// Closes the database and releases resources.
  Future<void> close();
}

/// Logical table names used by the attendance platform.
class AttendanceTables {
  static const attendance = 'attendance';
  static const syncQueue = 'sync_queue';
  static const audit = 'audit_log';

  static const all = [attendance, syncQueue, audit];
}

/// Pure in-memory [SecureDatabase]. Deep-copies rows on the way in and out so
/// callers can never mutate stored state by reference — matching the isolation
/// guarantees a real database provides.
class InMemorySecureDatabase implements SecureDatabase {
  final Map<String, Map<String, Map<String, dynamic>>> _tables = {};
  bool _open = false;

  @override
  Future<void> init() async {
    for (final t in AttendanceTables.all) {
      _tables.putIfAbsent(t, () => {});
    }
    _open = true;
  }

  Map<String, Map<String, dynamic>> _table(String table) {
    if (!_open) {
      throw StateError('SecureDatabase.init() must be called before use');
    }
    return _tables.putIfAbsent(table, () => {});
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> json) =>
      Map<String, dynamic>.from(json);

  @override
  Future<void> put(String table, String id, Map<String, dynamic> json) async =>
      _table(table)[id] = _copy(json);

  @override
  Future<Map<String, dynamic>?> get(String table, String id) async {
    final row = _table(table)[id];
    return row == null ? null : _copy(row);
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String table) async =>
      _table(table).values.map(_copy).toList();

  @override
  Future<void> delete(String table, String id) async =>
      _table(table).remove(id);

  @override
  Future<int> deleteWhereIdIn(String table, Iterable<String> ids) async {
    final t = _table(table);
    var removed = 0;
    for (final id in ids) {
      if (t.remove(id) != null) removed++;
    }
    return removed;
  }

  @override
  Future<void> close() async => _open = false;
}
