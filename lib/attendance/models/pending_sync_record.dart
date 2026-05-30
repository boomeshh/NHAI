// Offline sync queue entry (Phase 5 / Phase 11).
import 'enums.dart';

class PendingSyncRecord {
  final String syncId;

  /// e.g. 'attendance', 'employee', 'audit'.
  final String entityType;
  final String entityId;
  final Map<String, dynamic> payload;
  final SyncStatus status;
  final int attempts;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  final String? lastError;

  const PendingSyncRecord({
    required this.syncId,
    required this.entityType,
    required this.entityId,
    required this.payload,
    required this.createdAt,
    this.status = SyncStatus.pending,
    this.attempts = 0,
    this.lastAttemptAt,
    this.lastError,
  });

  PendingSyncRecord copyWith({
    SyncStatus? status,
    int? attempts,
    DateTime? lastAttemptAt,
    String? lastError,
  }) =>
      PendingSyncRecord(
        syncId: syncId,
        entityType: entityType,
        entityId: entityId,
        payload: payload,
        createdAt: createdAt,
        status: status ?? this.status,
        attempts: attempts ?? this.attempts,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
        'syncId': syncId,
        'entityType': entityType,
        'entityId': entityId,
        'payload': payload,
        'status': status.name,
        'attempts': attempts,
        'createdAt': createdAt.toIso8601String(),
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
        'lastError': lastError,
      };
}
