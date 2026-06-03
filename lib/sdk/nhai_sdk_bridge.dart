// NHAI SDK — bridge façade.
//
// The single entry point the platform channel calls. [NhaiSdkBridge.handle]
// dispatches a method name + argument map to the existing, FROZEN engine
// modules (enrollment, authentication, attendance, sync, dashboard) and returns
// a uniform [SdkResult]. It only *consumes* those modules — it never modifies
// face detection, recognition, the matcher, attendance, sync, or the dashboard.
//
// Camera-driven flows (enrollment capture, authentication capture) are reached
// through the injected [BiometricFlowLauncher] seam, so the whole bridge is
// unit-testable without a device and the on-device implementation simply drives
// the existing Flutter capture screens.
library;

import '../attendance/integration/attendance_module.dart';
import '../attendance/models/enums.dart';
import '../core/camera_frame.dart';
import '../core/enrollment_module/enrollment_module_interface.dart';
import '../models/auth_result.dart';
import '../models/face_pose.dart';
import 'nhai_sdk_contracts.dart';

/// Drives the Flutter biometric capture UI on behalf of the host. On-device
/// this navigates to the multi-pose enrollment / authentication screens; in
/// tests a fake returns canned captures. The AI pipeline stays entirely inside
/// these flows — the host never sees raw frames or embeddings.
abstract class BiometricFlowLauncher {
  /// Runs guided multi-pose capture and returns pose→frames (empty if the user
  /// cancelled).
  Future<Map<FacePose, List<CameraFrame>>> captureEnrollment(
      EmployeeFormData form);

  /// Runs the face + blink authentication flow and returns its result.
  Future<AuthResult> captureAuthentication();
}

class NhaiSdkBridge {
  final EnrollmentModuleInterface enrollment;
  final AttendanceModule attendance;
  final BiometricFlowLauncher launcher;
  final DateTime Function() clock;

  NhaiSdkBridge({
    required this.enrollment,
    required this.attendance,
    required this.launcher,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// Dispatches a platform-channel call. Never throws — every failure is mapped
  /// to a structured [SdkResult] the host can branch on.
  Future<SdkResult> handle(String method, Object? rawArgs) async {
    try {
      final args = asArgs(rawArgs);
      // NOTE: each branch is awaited so that errors thrown inside the async
      // handlers are caught here and mapped to a structured SdkResult — a bare
      // `return _handler(args)` would let the Future's error escape this guard.
      switch (method) {
        case SdkMethods.enrollEmployee:
          return await _enroll(args);
        case SdkMethods.authenticateEmployee:
          return await _authenticate(args);
        case SdkMethods.markAttendance:
          return await _mark(args);
        case SdkMethods.getAttendanceSummary:
          return await _summary(args);
        case SdkMethods.syncRecords:
          return await _sync(args);
        default:
          return SdkResult.failure(
              SdkCodes.unknownMethod, 'Unknown method "$method"');
      }
    } on SdkArgumentError catch (e) {
      return SdkResult.failure(SdkCodes.validationError, e.message);
    } catch (e) {
      return SdkResult.failure(SdkCodes.error, e.toString());
    }
  }

  // ── enrollEmployee ──────────────────────────────────────────────────────────
  Future<SdkResult> _enroll(Map<String, dynamic> args) async {
    final req = EnrollRequest.parse(args);
    final validation =
        enrollment.validateForm(req.employeeId, req.name, req.department);
    if (!validation.isValid) {
      return SdkResult.failure(
        SdkCodes.validationError,
        'Employee form failed validation',
        data: {'fieldErrors': validation.fieldErrors},
      );
    }
    final form = EmployeeFormData(
      employeeId: req.employeeId,
      name: req.name,
      department: req.department,
      allowOverwrite: req.allowOverwrite,
    );
    final posed = await launcher.captureEnrollment(form);
    if (posed.isEmpty) {
      return SdkResult.failure(
          SdkCodes.cancelled, 'Enrollment capture was cancelled');
    }
    final result = await enrollment.enrollMultiPose(form, posed);
    if (!result.success) {
      return SdkResult.failure(
          SdkCodes.error, result.errorMessage ?? 'Enrollment failed');
    }
    return SdkResult.success({
      'employeeId': req.employeeId,
      'name': req.name,
      'department': req.department,
      'templateCount': result.record?.templates?.length ?? 0,
      'poses': posed.keys.map((p) => p.label).toList(),
    }, message: 'Employee enrolled');
  }

  // ── authenticateEmployee ────────────────────────────────────────────────────
  Future<SdkResult> _authenticate(Map<String, dynamic> args) async {
    final result = await launcher.captureAuthentication();
    return _authEnvelope(result);
  }

  SdkResult _authEnvelope(AuthResult result) {
    final verified = result.classification == AuthClassification.verified &&
        result.matchedEmployeeId != null;
    if (!verified) {
      return SdkResult.failure(
        SdkCodes.notVerified,
        result.failureReason ?? 'Face not verified',
        data: {'verified': false, 'trustScore': result.trustScore},
      );
    }
    return SdkResult.success({
      'verified': true,
      'employeeId': result.matchedEmployeeId,
      'trustScore': result.trustScore,
    }, message: 'Identity verified');
  }

  // ── markAttendance ──────────────────────────────────────────────────────────
  Future<SdkResult> _mark(Map<String, dynamic> args) async {
    final req = MarkAttendanceRequest.parse(args);
    final forced = _parseForced(req.forced);

    // Identity is established INSIDE the Flutter flow — the host cannot forge a
    // verified result, so attendance can only be marked for a real, live face.
    final auth = await launcher.captureAuthentication();
    if (auth.classification != AuthClassification.verified ||
        auth.matchedEmployeeId == null) {
      return SdkResult.failure(
        SdkCodes.notVerified,
        auth.failureReason ?? 'Face not verified — attendance not marked',
        data: {'verified': false, 'trustScore': auth.trustScore},
      );
    }

    final outcome = await attendance.coordinator.markFromAuthResult(
      auth,
      now: clock(),
      forced: forced,
    );
    final record = outcome.engineResult?.record;
    final data = {
      'marked': outcome.marked,
      'employeeId': auth.matchedEmployeeId,
      'eventType': outcome.eventType?.name,
      'message': outcome.message,
      'trustScore': auth.trustScore,
      'attendanceId': record?.attendanceId,
    };
    return outcome.marked
        ? SdkResult.success(data, message: outcome.message)
        : SdkResult.failure(SdkCodes.error, outcome.message, data: data);
  }

  AttendanceEventType? _parseForced(String? forced) {
    switch (forced) {
      case null:
        return null;
      case 'checkIn':
        return AttendanceEventType.checkIn;
      case 'checkOut':
        return AttendanceEventType.checkOut;
      default:
        throw SdkArgumentError('forced must be "checkIn" or "checkOut"');
    }
  }

  // ── getAttendanceSummary ────────────────────────────────────────────────────
  Future<SdkResult> _summary(Map<String, dynamic> args) async {
    final req = SummaryRequest.parse(args, now: clock());
    final metrics = await attendance.dashboard.compute(req.date);
    final report = req.scope == 'monthly'
        ? await attendance.reports.monthlyReport(req.date.year, req.date.month)
        : await attendance.reports.dailyReport(req.date);
    return SdkResult.success({
      'scope': req.scope,
      'date': DateTime(req.date.year, req.date.month, req.date.day)
          .toIso8601String(),
      'metrics': metrics.toJson(),
      'report': report,
    });
  }

  // ── syncRecords ─────────────────────────────────────────────────────────────
  Future<SdkResult> _sync(Map<String, dynamic> args) async {
    final req = SyncRequest.parse(args);
    final now = clock();
    final sync = await attendance.syncPurgeEngine.sync(now: now);
    final data = <String, dynamic>{'sync': sync.toJson()};
    if (req.purge) {
      data['purge'] = (await attendance.syncPurgeEngine.purge(now)).toJson();
    }
    return SdkResult.success(data, message: 'Sync complete');
  }
}
