// Bridges a biometric AuthResult to an attendance mark (integration glue).
// Auto-resolves check-in vs check-out from the employee's open session (the
// turnstile pattern); an explicit event type can be forced.
import '../../models/auth_result.dart';
import '../models/enums.dart';
import '../repositories/attendance_repository.dart';
import '../services/attendance_engine.dart';

class AttendanceMarkOutcome {
  final bool marked;
  final AttendanceEventType? eventType;
  final String message;
  final AttendanceResult? engineResult;

  const AttendanceMarkOutcome({
    required this.marked,
    required this.message,
    this.eventType,
    this.engineResult,
  });
}

class AttendanceCoordinator {
  final AttendanceEngine engine;
  final AttendanceRepository attendance;
  final String deviceId;

  AttendanceCoordinator({
    required this.engine,
    required this.attendance,
    required this.deviceId,
  });

  Future<bool> hasOpenSession(String employeeId) async =>
      (await attendance.getOpenRecord(employeeId)) != null;

  /// Marks attendance from a verified [AuthResult]. The biometric blink gate
  /// has already passed by the time a VERIFIED result exists, so [blinkPassed]
  /// defaults to true. Returns a UI-friendly outcome.
  Future<AttendanceMarkOutcome> markFromAuthResult(
    AuthResult result, {
    required DateTime now,
    AttendanceEventType? forced,
    bool blinkPassed = true,
  }) async {
    final id = result.matchedEmployeeId;
    if (result.classification != AuthClassification.verified || id == null) {
      return const AttendanceMarkOutcome(
        marked: false,
        message: 'Face not verified — attendance not marked',
      );
    }

    final eventType = forced ??
        (await hasOpenSession(id)
            ? AttendanceEventType.checkOut
            : AttendanceEventType.checkIn);

    final ctx = VerificationContext(
      faceVerified: true,
      blinkPassed: blinkPassed,
      trustScore: result.trustScore,
      deviceId: deviceId,
      offlineMode: true,
    );

    final r = await engine.mark(
      employeeId: id,
      eventType: eventType,
      ctx: ctx,
      now: now,
    );

    final verb =
        eventType == AttendanceEventType.checkIn ? 'Checked in' : 'Checked out';
    return AttendanceMarkOutcome(
      marked: r.accepted,
      eventType: eventType,
      message: r.accepted
          ? '$verb successfully'
          : (r.rejectionReason ?? 'Attendance rejected'),
      engineResult: r,
    );
  }
}
