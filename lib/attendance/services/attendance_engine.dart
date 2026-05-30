// Core attendance engine (Phases 3, 4, 5). Enforces the check-in/out state
// machine and the full validation gate before any record is written, then
// persists locally and enqueues an offline sync entry. It never re-runs the
// biometric pipeline — it consumes a [VerificationContext] produced by it.
import '../../core/auth_engine/auth_engine_impl.dart' show AuthEngineImpl;
import '../models/anomaly_event.dart';
import '../models/attendance_record.dart';
import '../models/device_info.dart';
import '../models/enums.dart';
import '../models/pending_sync_record.dart';
import '../repositories/attendance_repository.dart';
import '../repositories/employee_repository.dart';
import '../sync/sync_queue.dart';
import 'anomaly_detector.dart';
import 'audit_service.dart';
import 'id_generator.dart';
import 'shift_service.dart';

/// The biometric outcome supplied by the existing face pipeline.
class VerificationContext {
  final bool faceVerified;
  final bool blinkPassed;
  final double trustScore;
  final String deviceId;
  final double? latitude;
  final double? longitude;
  final bool offlineMode;

  const VerificationContext({
    required this.faceVerified,
    required this.blinkPassed,
    required this.trustScore,
    required this.deviceId,
    this.latitude,
    this.longitude,
    this.offlineMode = true,
  });
}

class AttendanceResult {
  final bool accepted;
  final String? rejectionReason;
  final AttendanceRecord? record;
  final RiskLevel risk;
  final List<AnomalyEvent> anomalies;

  const AttendanceResult({
    required this.accepted,
    this.rejectionReason,
    this.record,
    this.risk = RiskLevel.low,
    this.anomalies = const [],
  });
}

class AttendanceEngine {
  final EmployeeRepository employees;
  final AttendanceRepository attendance;
  final AuditService audit;
  final ShiftService shifts;
  final AnomalyDetector anomalyDetector;
  final SyncQueue syncQueue;
  final IdGenerator ids;
  final String deviceId;

  final double recognitionThreshold;
  final bool requireBlink;
  final List<GeoFenceZone> geoFences;
  final Duration rapidRepeatWindow;

  AttendanceEngine({
    required this.employees,
    required this.attendance,
    required this.audit,
    required this.shifts,
    required this.anomalyDetector,
    required this.syncQueue,
    required this.ids,
    required this.deviceId,
    this.recognitionThreshold = AuthEngineImpl.defaultVerificationThreshold,
    this.requireBlink = true,
    this.geoFences = const [],
    this.rapidRepeatWindow = const Duration(seconds: 5),
  });

  Future<AttendanceResult> mark({
    required String employeeId,
    required AttendanceEventType eventType,
    required VerificationContext ctx,
    required DateTime now,
    String? shiftId,
  }) async {
    // 1. Employee must exist and be active.
    final employee = await employees.getById(employeeId);
    if (employee == null) {
      await audit.record(AuditEventType.authenticationFailed, now,
          employeeId: employeeId, details: {'reason': 'unknown employee'});
      return const AttendanceResult(
          accepted: false, rejectionReason: 'Unknown employee');
    }
    if (!employee.activeStatus) {
      await audit.record(AuditEventType.attendanceFailed, now,
          employeeId: employeeId, details: {'reason': 'inactive employee'});
      return const AttendanceResult(
          accepted: false, rejectionReason: 'Employee is inactive');
    }

    // 2. Biometric validation gate (Phase 4).
    final reason = _validate(ctx);
    if (reason != null) {
      await audit.record(AuditEventType.attendanceFailed, now,
          employeeId: employeeId,
          details: {'reason': reason, 'trustScore': ctx.trustScore});
      final anomalies =
          await anomalyDetector.onVerificationFailure(employeeId, now);
      return AttendanceResult(
        accepted: false,
        rejectionReason: reason,
        risk: _highestRisk(anomalies),
        anomalies: anomalies,
      );
    }

    // 3. Geo-fence (future-ready; only enforced when zones are configured).
    if (geoFences.isNotEmpty &&
        ctx.latitude != null &&
        ctx.longitude != null) {
      final inside =
          geoFences.any((z) => z.contains(ctx.latitude!, ctx.longitude!));
      if (!inside) {
        await audit.record(AuditEventType.attendanceFailed, now,
            employeeId: employeeId,
            details: {'reason': 'outside geo-fence'});
        final anomalies = await anomalyDetector.onLocationMismatch(
            employeeId, now, ctx.latitude, ctx.longitude);
        return AttendanceResult(
          accepted: false,
          rejectionReason: 'Outside permitted location',
          risk: RiskLevel.high,
          anomalies: anomalies,
        );
      }
    }

    // 4. Check-in / check-out state machine.
    final open = await attendance.getOpenRecord(employeeId);
    final AttendanceRecord record;
    if (eventType == AttendanceEventType.checkIn) {
      if (open != null) {
        await audit.record(AuditEventType.attendanceFailed, now,
            employeeId: employeeId,
            details: {'reason': 'already checked in'});
        final anomalies =
            await anomalyDetector.onMultipleCheckIn(employeeId, now);
        return AttendanceResult(
          accepted: false,
          rejectionReason: 'Already checked in — check out first',
          risk: _highestRisk(anomalies),
          anomalies: anomalies,
        );
      }
      final shift = await shifts.resolve(shiftId, now);
      record = AttendanceRecord(
        attendanceId: ids.next('ATT'),
        employeeId: employeeId,
        date: DateTime(now.year, now.month, now.day),
        checkInTime: now,
        verificationMethod: ctx.blinkPassed
            ? VerificationMethod.faceWithBlink
            : VerificationMethod.face,
        trustScore: ctx.trustScore,
        deviceId: deviceId,
        latitude: ctx.latitude,
        longitude: ctx.longitude,
        offlineMode: ctx.offlineMode,
        syncStatus: SyncStatus.pending,
        shiftId: shift?.shiftId,
        isLate: shift?.isLateCheckIn(now) ?? false,
      );
      await attendance.save(record);
    } else {
      if (open == null) {
        await audit.record(AuditEventType.attendanceFailed, now,
            employeeId: employeeId,
            details: {'reason': 'checkout before checkin'});
        return const AttendanceResult(
          accepted: false,
          rejectionReason: 'Cannot check out before checking in',
        );
      }
      record = open.copyWith(checkOutTime: now);
      await attendance.update(record);
    }

    // 5. Offline-first sync enqueue.
    await syncQueue.enqueue(PendingSyncRecord(
      syncId: ids.next('SYN'),
      entityType: 'attendance',
      entityId: record.attendanceId,
      payload: record.toJson(),
      createdAt: now,
    ));

    // 6. Audit the successful event.
    await audit.record(AuditEventType.attendanceMarked, now,
        employeeId: employeeId,
        details: {
          'event': eventType.name,
          'attendanceId': record.attendanceId,
          'trustScore': ctx.trustScore,
          'late': record.isLate,
        });

    // 7. Post-success anomaly checks (outside shift / rapid repeat).
    final shift = record.shiftId == null
        ? null
        : await shifts.getById(record.shiftId!);
    final outsideShift = shift != null && !shift.isWithin(now);
    final rapidRepeat = await _isRapidRepeat(employeeId, now, record);
    final anomalies = await anomalyDetector.onAttendanceMarked(
      employeeId,
      now,
      outsideShift: outsideShift,
      rapidRepeat: rapidRepeat,
    );

    return AttendanceResult(
      accepted: true,
      record: record,
      risk: _highestRisk(anomalies),
      anomalies: anomalies,
    );
  }

  String? _validate(VerificationContext ctx) {
    if (!ctx.faceVerified) return 'Face verification failed';
    if (requireBlink && !ctx.blinkPassed) return 'Liveness (blink) check failed';
    if (ctx.trustScore < recognitionThreshold) {
      return 'Trust score below threshold';
    }
    return null;
  }

  Future<bool> _isRapidRepeat(
      String employeeId, DateTime now, AttendanceRecord current) async {
    final records = await attendance.getByEmployee(employeeId);
    for (final r in records) {
      if (r.attendanceId == current.attendanceId) continue;
      final last = r.checkOutTime ?? r.checkInTime;
      final diff = now.difference(last).abs();
      if (diff <= rapidRepeatWindow) return true;
    }
    return false;
  }

  RiskLevel _highestRisk(List<AnomalyEvent> anomalies) {
    var risk = RiskLevel.low;
    for (final a in anomalies) {
      if (a.riskLevel == RiskLevel.high) return RiskLevel.high;
      if (a.riskLevel == RiskLevel.medium) risk = RiskLevel.medium;
    }
    return risk;
  }
}
