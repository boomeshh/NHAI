// Integration: the production NHAI attendance platform over DURABLE encrypted
// storage (exercised here via the in-memory SecureDatabase, the same interface
// the on-device SQLCipher backend implements).
//
//   enroll (biometric store) → check-in → PERSIST → restart → dashboard →
//   sync (PENDING→SYNCED) → purge (retire synced+expired)
//
// Proves persistence survives a fresh module instance over the same database
// and that the sync/purge engine drives records through their lifecycle —
// without touching the authentication pipeline.
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/attendance/integration/attendance_module.dart';
import 'package:nhai_auth/attendance/models/enums.dart';
import 'package:nhai_auth/attendance/models/pending_sync_record.dart';
import 'package:nhai_auth/attendance/persistence/secure_database.dart';
import 'package:nhai_auth/attendance/sync/sync_interfaces.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';

class _MemStorage implements StorageManagerInterface {
  final Map<String, EmployeeRecord> employees = {};
  @override
  Future<void> saveEmployeeRecord(EmployeeRecord r) async =>
      employees[r.employeeId] = r;
  @override
  Future<EmployeeRecord?> getEmployeeRecord(String id) async => employees[id];
  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async =>
      employees.values.toList();
  @override
  Future<bool> employeeExists(String id) async => employees.containsKey(id);
  @override
  Future<void> deleteEmployeeRecord(String id) async => employees.remove(id);
  @override
  Future<void> logAuthAttempt(AuthLogEntry e) async {}
  @override
  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async => const [];
  @override
  Future<void> logStorageError(String m) async {}
}

class _OkProvider implements SyncProvider {
  @override
  Future<SyncUploadResult> upload(PendingSyncRecord record) async =>
      const SyncUploadResult(success: true);
  @override
  Future<void> purgeSynced(List<String> entityIds) async {}
}

AuthResult _verified(String id, {double trust = 0.93}) => AuthResult(
      classification: AuthClassification.verified,
      trustScore: trust,
      matchedEmployeeId: id,
    );

void main() {
  test('persistent platform: check-in → durable restart → dashboard → '
      'sync → purge', () async {
    final now = DateTime(2026, 6, 1, 9);
    final database = InMemorySecureDatabase();
    final storage = _MemStorage();
    await storage.saveEmployeeRecord(EmployeeRecord(
      employeeId: 'EMP-1',
      name: 'Officer A',
      department: 'Patrol',
      embedding: FaceEmbedding(List<double>.filled(128, 0.1)),
      enrolledAt: DateTime.utc(2026, 1, 1),
    ));

    // ── Boot the platform over durable storage and check in ──────────────────
    final module = await AttendanceModule.persistent(
      database: database,
      storage: storage,
      syncProvider: _OkProvider(),
    );
    final checkIn =
        await module.coordinator.markFromAuthResult(_verified('EMP-1'), now: now);
    expect(checkIn.marked, isTrue);
    expect(checkIn.eventType, AttendanceEventType.checkIn);

    // ── Durability: a NEW module over the SAME database sees the record ───────
    final restarted = await AttendanceModule.persistent(
      database: database,
      storage: storage,
      syncProvider: _OkProvider(),
    );
    final persisted = await restarted.attendance.getByEmployee('EMP-1');
    expect(persisted, hasLength(1));
    expect(persisted.single.syncStatus, SyncStatus.pending);

    // ── Dashboard metrics include the durable record ─────────────────────────
    final dash = await restarted.dashboard.compute(now);
    expect(dash.presentToday, 1);
    expect(dash.lateToday, isA<int>());
    expect(dash.pendingSyncRecords, greaterThanOrEqualTo(1));

    // ── Sync drains the queue: PENDING → SYNCED on both queue and record ──────
    final syncResult = await restarted.syncPurgeEngine.sync(now: now);
    expect(syncResult.synced, greaterThanOrEqualTo(1));
    expect(syncResult.failed, 0);
    expect((await restarted.attendance.getByEmployee('EMP-1')).single.syncStatus,
        SyncStatus.synced);
    expect(await restarted.syncQueue.pending(), isEmpty);

    // ── Purge: not yet expired (today), so nothing is removed ────────────────
    final purgeNow = await restarted.syncPurgeEngine.purge(now);
    expect(purgeNow.attendancePurged, 0);
    // The synced queue entry is retired regardless of age.
    expect(purgeNow.queuePurged, greaterThanOrEqualTo(1));

    // ── Purge far in the future: the synced record is now expired ────────────
    final purgeLater =
        await restarted.syncPurgeEngine.purge(now.add(const Duration(days: 200)));
    expect(purgeLater.attendancePurged, 1);
    expect(await restarted.attendance.getByEmployee('EMP-1'), isEmpty);
  });
}
