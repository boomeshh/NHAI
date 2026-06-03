import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/attendance/models/attendance_record.dart';
import 'package:nhai_auth/attendance/models/enums.dart';
import 'package:nhai_auth/attendance/models/pending_sync_record.dart';
import 'package:nhai_auth/attendance/repositories/attendance_repository.dart';
import 'package:nhai_auth/attendance/sync/sync_interfaces.dart';
import 'package:nhai_auth/attendance/sync/sync_purge_engine.dart';
import 'package:nhai_auth/attendance/sync/sync_queue.dart';

class _FakeProvider implements SyncProvider {
  final SyncUploadResult Function(PendingSyncRecord) handler;
  int uploads = 0;
  _FakeProvider(this.handler);

  @override
  Future<SyncUploadResult> upload(PendingSyncRecord record) async {
    uploads++;
    return handler(record);
  }

  @override
  Future<void> purgeSynced(List<String> entityIds) async {}
}

AttendanceRecord _rec(String id, {DateTime? date, SyncStatus sync = SyncStatus.pending}) {
  final d = date ?? DateTime(2026, 6, 1);
  return AttendanceRecord(
    attendanceId: id,
    employeeId: 'EMP1',
    date: DateTime(d.year, d.month, d.day),
    checkInTime: d,
    verificationMethod: VerificationMethod.face,
    trustScore: 0.9,
    deviceId: 'DEV1',
    offlineMode: true,
    syncStatus: sync,
  );
}

PendingSyncRecord _pending(String id, String attendanceId) => PendingSyncRecord(
      syncId: id,
      entityType: 'attendance',
      entityId: attendanceId,
      payload: {'attendanceId': attendanceId},
      createdAt: DateTime(2026, 6, 1),
    );

void main() {
  final now = DateTime(2026, 6, 1, 9);

  group('SyncPurgeEngine.sync — offline', () {
    test('no provider → entries stay PENDING, reported as skippedOffline', () async {
      final queue = InMemorySyncQueue();
      await queue.enqueue(_pending('S1', 'A1'));
      final engine = SyncPurgeEngine(
          queue: queue, attendance: InMemoryAttendanceRepository());

      final r = await engine.sync(now: now);
      expect(r.isOffline, isTrue);
      expect(r.skippedOffline, 1);
      expect((await queue.pending()), hasLength(1)); // unchanged
    });
  });

  group('SyncPurgeEngine.sync — online', () {
    test('success → queue SYNCED and attendance record flipped to synced', () async {
      final queue = InMemorySyncQueue();
      final attendance = InMemoryAttendanceRepository();
      await attendance.save(_rec('A1'));
      await queue.enqueue(_pending('S1', 'A1'));

      final engine = SyncPurgeEngine(
        queue: queue,
        attendance: attendance,
        provider: _FakeProvider((_) => const SyncUploadResult(success: true)),
      );

      final r = await engine.sync(now: now);
      expect(r.processed, 1);
      expect(r.synced, 1);
      expect(r.failed, 0);
      expect((await queue.byStatus(SyncStatus.synced)), hasLength(1));
      expect((await attendance.getById('A1'))!.syncStatus, SyncStatus.synced);
    });

    test('failure → FAILED with attempts incremented; retried next drain', () async {
      final queue = InMemorySyncQueue();
      await queue.enqueue(_pending('S1', 'A1'));
      final engine = SyncPurgeEngine(
        queue: queue,
        attendance: InMemoryAttendanceRepository(),
        provider:
            _FakeProvider((_) => const SyncUploadResult(success: false, error: 'net')),
        retryPolicy: const RetryPolicy(maxAttempts: 2),
      );

      final r1 = await engine.sync(now: now);
      expect(r1.failed, 1);
      var rec = (await queue.byStatus(SyncStatus.failed)).single;
      expect(rec.attempts, 1);
      expect(rec.lastError, 'net');

      // Second drain retries the FAILED (1 < maxAttempts 2).
      final r2 = await engine.sync(now: now);
      expect(r2.processed, 1);
      rec = (await queue.byStatus(SyncStatus.failed)).single;
      expect(rec.attempts, 2);

      // Third drain: attempts (2) not < maxAttempts (2) → no longer retried.
      final r3 = await engine.sync(now: now);
      expect(r3.processed, 0);
    });

    test('conflict resolved by last-write-wins counts as synced', () async {
      final queue = InMemorySyncQueue();
      final attendance = InMemoryAttendanceRepository();
      await attendance.save(_rec('A1'));
      await queue.enqueue(_pending('S1', 'A1'));
      final engine = SyncPurgeEngine(
        queue: queue,
        attendance: attendance,
        provider: _FakeProvider(
            (_) => const SyncUploadResult(success: false, conflict: true)),
      );

      final r = await engine.sync(now: now);
      expect(r.conflicts, 1);
      expect(r.synced, 1);
      expect((await attendance.getById('A1'))!.syncStatus, SyncStatus.synced);
    });

    test('a thrown provider error is treated as a failure, not a crash', () async {
      final queue = InMemorySyncQueue();
      await queue.enqueue(_pending('S1', 'A1'));
      final engine = SyncPurgeEngine(
        queue: queue,
        attendance: InMemoryAttendanceRepository(),
        provider: _FakeProvider((_) => throw Exception('boom')),
      );
      final r = await engine.sync(now: now);
      expect(r.failed, 1);
      expect((await queue.byStatus(SyncStatus.failed)).single.lastError,
          contains('boom'));
    });
  });

  group('SyncPurgeEngine.purge', () {
    test('removes synced+expired attendance, keeps recent, retires synced queue',
        () async {
      final queue = InMemorySyncQueue();
      final attendance = InMemoryAttendanceRepository();
      // Synced but old (≈5 months before now) → purge.
      await attendance.save(
          _rec('OLD', date: DateTime(2026, 1, 1), sync: SyncStatus.synced));
      // Synced and recent → keep.
      await attendance.save(
          _rec('NEW', date: DateTime(2026, 6, 1), sync: SyncStatus.synced));
      // Pending old → keep (not yet synced).
      await attendance.save(
          _rec('PEND', date: DateTime(2026, 1, 1), sync: SyncStatus.pending));

      await queue.enqueue(_pending('SsyncedDone', 'OLD'));
      await queue.update((await queue.getAll())
          .single
          .copyWith(status: SyncStatus.synced));
      await queue.enqueue(_pending('SstillPending', 'PEND'));

      final engine = SyncPurgeEngine(
        queue: queue,
        attendance: attendance,
        retention: const Duration(days: 90),
      );

      final result = await engine.purge(now);
      expect(result.attendancePurged, 1); // only OLD
      expect(result.queuePurged, 1); // only the synced queue entry

      expect(await attendance.getById('OLD'), isNull);
      expect(await attendance.getById('NEW'), isNotNull);
      expect(await attendance.getById('PEND'), isNotNull);
      expect(await queue.pending(), hasLength(1)); // SstillPending remains
    });
  });
}
