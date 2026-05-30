// Immutable audit log entry (Phase 6). Fields are final and there is no setter
// or copyWith — entries are append-only.
import 'enums.dart';

class AttendanceAuditLog {
  final String auditId;
  final AuditEventType eventType;
  final String? employeeId;
  final DateTime timestamp;
  final String deviceId;
  final Map<String, dynamic> details;

  const AttendanceAuditLog({
    required this.auditId,
    required this.eventType,
    required this.timestamp,
    required this.deviceId,
    this.employeeId,
    this.details = const {},
  });

  Map<String, dynamic> toJson() => {
        'auditId': auditId,
        'eventType': eventType.name,
        'employeeId': employeeId,
        'timestamp': timestamp.toIso8601String(),
        'deviceId': deviceId,
        'details': details,
      };

  factory AttendanceAuditLog.fromJson(Map<String, dynamic> j) =>
      AttendanceAuditLog(
        auditId: j['auditId'] as String,
        eventType: enumByName(AuditEventType.values, j['eventType'] as String?,
            AuditEventType.attendanceMarked),
        employeeId: j['employeeId'] as String?,
        timestamp: DateTime.parse(j['timestamp'] as String),
        deviceId: j['deviceId'] as String,
        details: Map<String, dynamic>.from(j['details'] as Map? ?? const {}),
      );
}
