// Offline sync queue (Phase 5 / Phase 11). Interface + in-memory implementation.
import '../models/enums.dart';
import '../models/pending_sync_record.dart';

abstract class SyncQueue {
  Future<void> enqueue(PendingSyncRecord record);
  Future<List<PendingSyncRecord>> pending();
  Future<List<PendingSyncRecord>> byStatus(SyncStatus status);
  Future<void> update(PendingSyncRecord record);
  Future<List<PendingSyncRecord>> getAll();

  /// Removes queue entries by syncId; returns the count removed. Used by the
  /// purge engine to retire entries whose data has been synced.
  Future<int> deleteByIds(Iterable<String> syncIds);
}

class InMemorySyncQueue implements SyncQueue {
  final Map<String, PendingSyncRecord> _store = {};

  @override
  Future<void> enqueue(PendingSyncRecord record) async =>
      _store[record.syncId] = record;

  @override
  Future<List<PendingSyncRecord>> pending() async =>
      byStatus(SyncStatus.pending);

  @override
  Future<List<PendingSyncRecord>> byStatus(SyncStatus status) async =>
      _store.values.where((r) => r.status == status).toList();

  @override
  Future<void> update(PendingSyncRecord record) async =>
      _store[record.syncId] = record;

  @override
  Future<List<PendingSyncRecord>> getAll() async => _store.values.toList();

  @override
  Future<int> deleteByIds(Iterable<String> syncIds) async {
    var removed = 0;
    for (final id in syncIds) {
      if (_store.remove(id) != null) removed++;
    }
    return removed;
  }
}
