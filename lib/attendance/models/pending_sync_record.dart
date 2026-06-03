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

  factory PendingSyncRecord.fromJson(Map<String, dynamic> j) =>
      PendingSyncRecord(
        syncId: j['syncId'] as String,
        entityType: j['entityType'] as String,
        entityId: j['entityId'] as String,
        payload: Map<String, dynamic>.from(j['payload'] as Map? ?? const {}),
        status: enumByName(
            SyncStatus.values, j['status'] as String?, SyncStatus.pending),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(j['createdAt'] as String),
        lastAttemptAt: j['lastAttemptAt'] == null
            ? null
            : DateTime.parse(j['lastAttemptAt'] as String),
        lastError: j['lastError'] as String?,
      );
}
