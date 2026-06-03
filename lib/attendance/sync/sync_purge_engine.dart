// Sync & Purge engine (NHAI offline-first requirement).
//
// DRAIN: pushes PENDING (and retry-eligible FAILED) queue entries through the
// injected [SyncProvider], transitioning each to SYNCED or FAILED per the
// [RetryPolicy], and flips the corresponding attendance record's syncStatus to
// SYNCED. With no provider injected the device stays fully offline and entries
// remain PENDING (no data loss).
//
// PURGE: bounds on-device storage by deleting attendance records that are both
// SYNCED and older than the retention window, and by retiring SYNCED queue
// entries whose upload is complete.
//
// Pure orchestration over the repository / queue / provider interfaces — no
// cloud code, no changes to the matcher, threshold, or authentication.
import '../models/enums.dart';
import '../repositories/attendance_repository.dart';
import 'sync_interfaces.dart';
import 'sync_queue.dart';

/// Outcome of one drain pass.
class SyncRunResult {
  final int processed;
  final int synced;
  final int failed;
  final int conflicts;

  /// Entries left untouched because the device is offline (no provider).
  final int skippedOffline;

  const SyncRunResult({
    this.processed = 0,
    this.synced = 0,
    this.failed = 0,
    this.conflicts = 0,
    this.skippedOffline = 0,
  });

  bool get isOffline => skippedOffline > 0 && processed == 0;

  Map<String, dynamic> toJson() => {
        'processed': processed,
        'synced': synced,
        'failed': failed,
        'conflicts': conflicts,
        'skippedOffline': skippedOffline,
      };
}

/// Outcome of one purge pass.
class PurgeResult {
  final int attendancePurged;
  final int queuePurged;
  const PurgeResult(this.attendancePurged, this.queuePurged);

  Map<String, dynamic> toJson() =>
      {'attendancePurged': attendancePurged, 'queuePurged': queuePurged};
}

class SyncPurgeEngine {
  final SyncQueue queue;
  final AttendanceRepository attendance;

  /// Remote transport. Null ⇒ fully offline (entries remain PENDING).
  final SyncProvider? provider;
  final ConflictResolver conflictResolver;
  final RetryPolicy retryPolicy;

  /// Synced records older than this are eligible for purge.
  final Duration retention;

  SyncPurgeEngine({
    required this.queue,
    required this.attendance,
    this.provider,
    ConflictResolver? conflictResolver,
    this.retryPolicy = const RetryPolicy(),
    this.retention = const Duration(days: 90),
  }) : conflictResolver = conflictResolver ?? LastWriteWinsResolver();

  bool get isOnlineCapable => provider != null;

  /// Drains PENDING + retry-eligible FAILED entries through [provider].
  Future<SyncRunResult> sync({required DateTime now}) async {
    final pending = await queue.pending();
    final retryable = (await queue.byStatus(SyncStatus.failed))
        .where((r) => retryPolicy.shouldRetry(r.attempts))
        .toList();
    final toProcess = [...pending, ...retryable];

    final p = provider;
    if (p == null) {
      // Offline: nothing changes, everything stays queued.
      return SyncRunResult(skippedOffline: toProcess.length);
    }

    var synced = 0, failed = 0, conflicts = 0;
    for (final record in toProcess) {
      SyncUploadResult result;
      try {
        result = await p.upload(record);
      } catch (e) {
        result = SyncUploadResult(success: false, error: e.toString());
      }

      final bool resolvedAsSuccess = result.success ||
          (result.conflict &&
              conflictResolver.localWins(record, result.remoteVersion)) ||
          // A conflict the remote already won is still "resolved" — the local
          // entry is reconciled and need not be retried.
          result.conflict;

      if (result.conflict) conflicts++;

      if (resolvedAsSuccess) {
        synced++;
        await queue.update(record.copyWith(
          status: SyncStatus.synced,
          attempts: record.attempts + 1,
          lastAttemptAt: now,
        ));
        await _markEntitySynced(record.entityType, record.entityId);
      } else {
        failed++;
        await queue.update(record.copyWith(
          status: SyncStatus.failed,
          attempts: record.attempts + 1,
          lastAttemptAt: now,
          lastError: result.error ?? 'upload failed',
        ));
      }
    }

    return SyncRunResult(
      processed: toProcess.length,
      synced: synced,
      failed: failed,
      conflicts: conflicts,
    );
  }

  Future<void> _markEntitySynced(String entityType, String entityId) async {
    if (entityType != 'attendance') return;
    final rec = await attendance.getById(entityId);
    if (rec != null && rec.syncStatus != SyncStatus.synced) {
      await attendance.update(rec.copyWith(syncStatus: SyncStatus.synced));
    }
  }

  /// Purges SYNCED attendance older than [retention] and retires SYNCED queue
  /// entries. Recent synced records are kept for offline reporting.
  Future<PurgeResult> purge(DateTime now) async {
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(retention);
    final synced = await attendance.getBySyncStatus(SyncStatus.synced);
    final expiredIds = synced
        .where((r) => r.date.isBefore(cutoff))
        .map((r) => r.attendanceId)
        .toList();
    final attendancePurged = await attendance.deleteByIds(expiredIds);

    final syncedQueue = await queue.byStatus(SyncStatus.synced);
    final queuePurged =
        await queue.deleteByIds(syncedQueue.map((r) => r.syncId).toList());

    return PurgeResult(attendancePurged, queuePurged);
  }
}
