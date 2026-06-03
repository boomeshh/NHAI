import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/attendance/models/attendance_audit_log.dart';
import 'package:nhai_auth/attendance/models/attendance_record.dart';
import 'package:nhai_auth/attendance/models/enums.dart';
import 'package:nhai_auth/attendance/models/pending_sync_record.dart';
import 'package:nhai_auth/attendance/persistence/secure_database.dart';
import 'package:nhai_auth/attendance/repositories/persistent_attendance_repository.dart';
import 'package:nhai_auth/attendance/repositories/persistent_audit_repository.dart';
import 'package:nhai_auth/attendance/sync/persistent_sync_queue.dart';

AttendanceRecord _rec(
  String id,
  String emp, {
  DateTime? date,
  SyncStatus sync = SyncStatus.pending,
  bool late = false,
}) {
  final d = date ?? DateTime(2026, 6, 1);
  return AttendanceRecord(
    attendanceId: id,
    employeeId: emp,
    date: DateTime(d.year, d.month, d.day),
    checkInTime: d,
    verificationMethod: VerificationMethod.face,
    trustScore: 0.91,
    deviceId: 'DEV1',
    offlineMode: true,
    syncStatus: sync,
    isLate: late,
  );
}

void main() {
  group('InMemorySecureDatabase', () {
    test('requires init before use', () async {
      final db = InMemorySecureDatabase();
      expect(() => db.put('attendance', 'x', {}), throwsStateError);
    });

    test('put/get/getAll/delete round-trip with value isolation', () async {
      final db = InMemorySecureDatabase();
      await db.init();
      final json = {'a': 1};
      await db.put('attendance', 'k1', json);
      json['a'] = 999; // mutating the source must NOT affect stored copy
      final got = await db.get('attendance', 'k1');
      expect(got!['a'], 1);

      got['a'] = 42; // mutating the returned copy must NOT affect storage
      expect((await db.get('attendance', 'k1'))!['a'], 1);

      expect(await db.getAll('attendance'), hasLength(1));
      await db.delete('attendance', 'k1');
      expect(await db.get('attendance', 'k1'), isNull);
    });

    test('deleteWhereIdIn returns count removed', () async {
      final db = InMemorySecureDatabase();
      await db.init();
      await db.put('sync_queue', 'a', {});
      await db.put('sync_queue', 'b', {});
      await db.put('sync_queue', 'c', {});
      expect(await db.deleteWhereIdIn('sync_queue', ['a', 'b', 'zzz']), 2);
      expect(await db.getAll('sync_queue'), hasLength(1));
    });
  });

  group('PersistentAttendanceRepository', () {
    late InMemorySecureDatabase db;
    late PersistentAttendanceRepository repo;

    setUp(() async {
      db = InMemorySecureDatabase();
      await db.init();
      repo = PersistentAttendanceRepository(db);
    });

    test('save + getById survives a fresh repo over the same database', () async {
      await repo.save(_rec('A1', 'EMP1'));
      // Simulate an app restart: a new repository instance over the same DB.
      final repo2 = PersistentAttendanceRepository(db);
      final got = await repo2.getById('A1');
      expect(got, isNotNull);
      expect(got!.employeeId, 'EMP1');
      expect(got.trustScore, 0.91);
    });

    test('queries: byDate, byEmployee, byDateRange, openRecord, bySyncStatus',
        () async {
      await repo.save(_rec('A1', 'EMP1', date: DateTime(2026, 6, 1)));
      await repo.save(_rec('A2', 'EMP2',
          date: DateTime(2026, 6, 2), sync: SyncStatus.synced));
      await repo.save(_rec('A3', 'EMP1', date: DateTime(2026, 6, 3)));

      expect(await repo.getByDate(DateTime(2026, 6, 1)), hasLength(1));
      expect(await repo.getByEmployee('EMP1'), hasLength(2));
      expect(
          await repo.getByDateRange(DateTime(2026, 6, 1), DateTime(2026, 6, 2)),
          hasLength(2));
      expect((await repo.getBySyncStatus(SyncStatus.synced)).single.attendanceId,
          'A2');

      // open record = no checkout
      final open = await repo.getOpenRecord('EMP1');
      expect(open, isNotNull);
    });

    test('update overwrites and deleteByIds removes', () async {
      await repo.save(_rec('A1', 'EMP1'));
      await repo.update(
          (await repo.getById('A1'))!.copyWith(syncStatus: SyncStatus.synced));
      expect((await repo.getById('A1'))!.syncStatus, SyncStatus.synced);
      expect(await repo.deleteByIds(['A1']), 1);
      expect(await repo.getById('A1'), isNull);
    });
  });

  group('PersistentSyncQueue', () {
    test('enqueue/byStatus/update/delete + fromJson round-trip', () async {
      final db = InMemorySecureDatabase();
      await db.init();
      final q = PersistentSyncQueue(db);
      final rec = PendingSyncRecord(
        syncId: 'S1',
        entityType: 'attendance',
        entityId: 'A1',
        payload: {'attendanceId': 'A1'},
        createdAt: DateTime(2026, 6, 1),
      );
      await q.enqueue(rec);
      expect(await q.pending(), hasLength(1));

      // Restart: new queue over same DB rehydrates via fromJson.
      final q2 = PersistentSyncQueue(db);
      final loaded = (await q2.pending()).single;
      expect(loaded.entityId, 'A1');
      expect(loaded.payload['attendanceId'], 'A1');

      await q2.update(loaded.copyWith(status: SyncStatus.synced, attempts: 1));
      expect(await q2.pending(), isEmpty);
      expect(await q2.byStatus(SyncStatus.synced), hasLength(1));
      expect(await q2.deleteByIds(['S1']), 1);
      expect(await q2.getAll(), isEmpty);
    });
  });

  group('PersistentAuditRepository', () {
    test('append + getAll + getByEmployee persist across instances', () async {
      final db = InMemorySecureDatabase();
      await db.init();
      final audit = PersistentAuditRepository(db);
      await audit.append(AttendanceAuditLog(
        auditId: 'L1',
        eventType: AuditEventType.attendanceMarked,
        timestamp: DateTime(2026, 6, 1),
        deviceId: 'DEV1',
        employeeId: 'EMP1',
      ));
      final audit2 = PersistentAuditRepository(db);
      expect(await audit2.getAll(), hasLength(1));
      expect(await audit2.getByEmployee('EMP1'), hasLength(1));
      expect(await audit2.getByEmployee('NOPE'), isEmpty);
    });
  });
}
