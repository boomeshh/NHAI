// Persistent [SyncQueue] backed by a [SecureDatabase]. Queue entries survive
// app restarts so PENDING / FAILED uploads are retried after the device comes
// back online. Stored as JSON keyed by syncId.
import '../models/enums.dart';
import '../models/pending_sync_record.dart';
import '../persistence/secure_database.dart';
import 'sync_queue.dart';

class PersistentSyncQueue implements SyncQueue {
  final SecureDatabase db;
  static const _table = AttendanceTables.syncQueue;

  PersistentSyncQueue(this.db);

  @override
  Future<void> enqueue(PendingSyncRecord record) async =>
      db.put(_table, record.syncId, record.toJson());

  @override
  Future<void> update(PendingSyncRecord record) async =>
      db.put(_table, record.syncId, record.toJson());

  Future<List<PendingSyncRecord>> _all() async {
    final rows = await db.getAll(_table);
    return rows.map(PendingSyncRecord.fromJson).toList();
  }

  @override
  Future<List<PendingSyncRecord>> pending() async => byStatus(SyncStatus.pending);

  @override
  Future<List<PendingSyncRecord>> byStatus(SyncStatus status) async =>
      (await _all()).where((r) => r.status == status).toList();

  @override
  Future<List<PendingSyncRecord>> getAll() async => _all();

  /// Removes queue entries by id (used after a successful purge of synced data).
  @override
  Future<int> deleteByIds(Iterable<String> syncIds) =>
      db.deleteWhereIdIn(_table, syncIds);
}
