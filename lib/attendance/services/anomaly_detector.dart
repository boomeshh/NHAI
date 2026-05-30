// Suspicious-attendance detection (Phase 9). Emits risk-graded anomaly events
// and mirrors them into the audit trail.
import '../models/anomaly_event.dart';
import '../models/enums.dart';
import '../repositories/anomaly_repository.dart';
import '../repositories/audit_repository.dart';
import 'audit_service.dart';
import 'id_generator.dart';

class AnomalyDetector {
  final AnomalyRepository anomalies;
  final AuditRepository auditRepository;
  final AuditService audit;
  final IdGenerator ids;
  final String deviceId;

  final Duration failureWindow;
  final int mediumFailureThreshold;
  final int highFailureThreshold;

  AnomalyDetector({
    required this.anomalies,
    required this.auditRepository,
    required this.audit,
    required this.ids,
    required this.deviceId,
    this.failureWindow = const Duration(minutes: 10),
    this.mediumFailureThreshold = 3,
    this.highFailureThreshold = 5,
  });

  Future<AnomalyEvent> _emit(
    AnomalyType type,
    RiskLevel risk,
    String? employeeId,
    DateTime now,
    Map<String, dynamic> details,
  ) async {
    final event = AnomalyEvent(
      anomalyId: ids.next('ANO'),
      type: type,
      riskLevel: risk,
      employeeId: employeeId,
      timestamp: now,
      deviceId: deviceId,
      details: details,
    );
    await anomalies.add(event);
    await audit.record(AuditEventType.anomalyDetected, now,
        employeeId: employeeId,
        details: {'type': type.name, 'risk': risk.name, ...details});
    return event;
  }

  /// Counts recent verification/authentication failures for the employee and
  /// raises a graded [AnomalyType.repeatedVerificationFailure] if over threshold.
  /// (The current failure is assumed already recorded in the audit trail.)
  Future<List<AnomalyEvent>> onVerificationFailure(
      String employeeId, DateTime now) async {
    final cutoff = now.subtract(failureWindow);
    final logs = await auditRepository.getByEmployee(employeeId);
    final failures = logs
        .where((l) =>
            (l.eventType == AuditEventType.attendanceFailed ||
                l.eventType == AuditEventType.authenticationFailed) &&
            !l.timestamp.isBefore(cutoff))
        .length;
    if (failures >= highFailureThreshold) {
      return [
        await _emit(AnomalyType.repeatedVerificationFailure, RiskLevel.high,
            employeeId, now, {'failures': failures})
      ];
    }
    if (failures >= mediumFailureThreshold) {
      return [
        await _emit(AnomalyType.repeatedVerificationFailure, RiskLevel.medium,
            employeeId, now, {'failures': failures})
      ];
    }
    return [];
  }

  Future<List<AnomalyEvent>> onMultipleCheckIn(
          String employeeId, DateTime now) async =>
      [
        await _emit(
            AnomalyType.multipleCheckIn, RiskLevel.high, employeeId, now, {})
      ];

  Future<List<AnomalyEvent>> onLocationMismatch(
          String employeeId, DateTime now, double? lat, double? lng) async =>
      [
        await _emit(AnomalyType.locationMismatch, RiskLevel.high, employeeId,
            now, {'lat': lat, 'lng': lng})
      ];

  Future<List<AnomalyEvent>> onAttendanceMarked(
    String employeeId,
    DateTime now, {
    required bool outsideShift,
    required bool rapidRepeat,
  }) async {
    final out = <AnomalyEvent>[];
    if (outsideShift) {
      out.add(await _emit(
          AnomalyType.outsideShift, RiskLevel.medium, employeeId, now, {}));
    }
    if (rapidRepeat) {
      out.add(await _emit(AnomalyType.rapidRepeatedAuthentication,
          RiskLevel.medium, employeeId, now, {}));
    }
    return out;
  }
}
