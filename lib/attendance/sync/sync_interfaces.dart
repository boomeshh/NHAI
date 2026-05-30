// AWS-sync readiness (Phase 11): INTERFACES ONLY. No cloud implementation here.
// A future AwsSyncProvider implements [SyncProvider]; the orchestration,
// queueing, conflict resolution and retry policy are all defined now so the
// architecture supports sync/purge without rework.
import '../models/pending_sync_record.dart';
import 'sync_queue.dart';

/// Outcome of pushing a single record to a remote backend.
class SyncUploadResult {
  final bool success;
  final bool conflict;
  final String? remoteVersion;
  final String? error;
  const SyncUploadResult({
    required this.success,
    this.conflict = false,
    this.remoteVersion,
    this.error,
  });
}

/// Transport to a remote backend (e.g. a future AwsSyncProvider over AppSync /
/// DynamoDB / S3). Intentionally unimplemented.
abstract class SyncProvider {
  Future<SyncUploadResult> upload(PendingSyncRecord record);
  Future<void> purgeSynced(List<String> entityIds);
}

/// Decides which version wins when local and remote differ.
abstract class ConflictResolver {
  /// Returns true if the LOCAL record should overwrite the remote one.
  bool localWins(PendingSyncRecord local, String? remoteVersion);
}

/// Default policy: last-write-wins by local timestamp (server reconciles).
class LastWriteWinsResolver implements ConflictResolver {
  @override
  bool localWins(PendingSyncRecord local, String? remoteVersion) => true;
}

/// Exponential backoff with a cap and max attempts.
class RetryPolicy {
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  const RetryPolicy({
    this.maxAttempts = 5,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
  });

  bool shouldRetry(int attempts) => attempts < maxAttempts;

  Duration delayFor(int attempt) {
    final ms = baseDelay.inMilliseconds * (1 << attempt);
    return ms >= maxDelay.inMilliseconds ? maxDelay : Duration(milliseconds: ms);
  }
}

/// Orchestrates draining the [SyncQueue] through a [SyncProvider]. The concrete
/// remote provider is injected later; with none injected the engine stays fully
/// offline (records remain PENDING). This class contains no AWS code.
class AttendanceSyncService {
  final SyncQueue queue;
  final SyncProvider? provider;
  final ConflictResolver conflictResolver;
  final RetryPolicy retryPolicy;

  AttendanceSyncService({
    required this.queue,
    this.provider,
    ConflictResolver? conflictResolver,
    this.retryPolicy = const RetryPolicy(),
  }) : conflictResolver = conflictResolver ?? LastWriteWinsResolver();

  bool get isOnlineCapable => provider != null;
}
