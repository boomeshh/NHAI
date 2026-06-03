// Integration: the NHAI SDK bridge dispatching all five public methods end to
// end against the REAL in-memory attendance module, with fakes only for the
// camera-driven enrollment module and the capture launcher. Proves the host
// boundary works without touching detection/recognition/matcher/attendance.
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/attendance/integration/attendance_module.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_interface.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/face_pose.dart';
import 'package:nhai_auth/models/face_template.dart';
import 'package:nhai_auth/sdk/nhai_sdk_bridge.dart';
import 'package:nhai_auth/sdk/nhai_sdk_contracts.dart';

class _MemStorage implements StorageManagerInterface {
  final Map<String, EmployeeRecord> employees = {};
  @override
  Future<void> saveEmployeeRecord(EmployeeRecord r) async =>
      employees[r.employeeId] = r;
  @override
  Future<EmployeeRecord?> getEmployeeRecord(String id) async => employees[id];
  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async =>
      employees.values.toList();
  @override
  Future<bool> employeeExists(String id) async => employees.containsKey(id);
  @override
  Future<void> deleteEmployeeRecord(String id) async => employees.remove(id);
  @override
  Future<void> logAuthAttempt(AuthLogEntry e) async {}
  @override
  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async => const [];
  @override
  Future<void> logStorageError(String m) async {}
}

class _FakeEnrollment implements EnrollmentModuleInterface {
  bool formValid = true;
  bool enrollSucceeds = true;

  @override
  ValidationResult validateForm(String id, String name, String dept) =>
      ValidationResult(
          isValid: formValid,
          fieldErrors: formValid ? const {} : const {'employeeId': 'taken'});

  @override
  CameraFrame selectBestFrame(List<CameraFrame> frames) => frames.first;

  @override
  Future<EnrollmentResult> enroll(
          EmployeeFormData f, List<CameraFrame> frames) async =>
      enrollMultiPose(f, {FacePose.frontal: frames});

  @override
  Future<EnrollmentResult> enrollMultiPose(
      EmployeeFormData f, Map<FacePose, List<CameraFrame>> posed) async {
    if (!enrollSucceeds) {
      return const EnrollmentResult(success: false, errorMessage: 'storage full');
    }
    final templates = [
      for (final pose in posed.keys)
        FaceTemplate(
          embedding: FaceEmbedding(List<double>.filled(128, 0.1)),
          poseLabel: pose,
          yaw: 0,
          pitch: 0,
          qualityScore: 80,
          createdAt: DateTime.utc(2026, 1, 1),
          pipelineVersion: 3,
        ),
    ];
    return EnrollmentResult(
      success: true,
      record: EmployeeRecord(
        employeeId: f.employeeId,
        name: f.name,
        department: f.department,
        embedding: FaceEmbedding(List<double>.filled(128, 0.1)),
        enrolledAt: DateTime.utc(2026, 1, 1),
        templates: templates,
      ),
    );
  }
}

class _FakeLauncher implements BiometricFlowLauncher {
  Map<FacePose, List<CameraFrame>> enrollReturn;
  AuthResult authReturn;
  _FakeLauncher({required this.enrollReturn, required this.authReturn});

  @override
  Future<Map<FacePose, List<CameraFrame>>> captureEnrollment(
          EmployeeFormData form) async =>
      enrollReturn;

  @override
  Future<AuthResult> captureAuthentication() async => authReturn;
}

CameraFrame _frame() => const CameraFrame(
    bytes: [1, 2, 3], width: 112, height: 112, sharpnessScore: 50);

AuthResult _verified(String id) => AuthResult(
    classification: AuthClassification.verified,
    trustScore: 0.93,
    matchedEmployeeId: id);

AuthResult _rejected() => const AuthResult(
    classification: AuthClassification.failed,
    trustScore: 0.4,
    failureReason: 'Face not recognized');

void main() {
  final now = DateTime(2026, 6, 1, 9);

  late _MemStorage storage;
  late AttendanceModule attendance;
  late _FakeEnrollment enrollment;
  late _FakeLauncher launcher;
  late NhaiSdkBridge bridge;

  Future<void> setup({AuthResult? auth}) async {
    storage = _MemStorage();
    await storage.saveEmployeeRecord(EmployeeRecord(
      employeeId: 'EMP-1',
      name: 'Officer A',
      department: 'Patrol',
      embedding: FaceEmbedding(List<double>.filled(128, 0.1)),
      enrolledAt: DateTime.utc(2026, 1, 1),
    ));
    attendance = AttendanceModule.inMemory(storage: storage);
    enrollment = _FakeEnrollment();
    launcher = _FakeLauncher(
      enrollReturn: {
        FacePose.frontal: [_frame()],
        FacePose.left: [_frame()],
      },
      authReturn: auth ?? _verified('EMP-1'),
    );
    bridge = NhaiSdkBridge(
      enrollment: enrollment,
      attendance: attendance,
      launcher: launcher,
      clock: () => now,
    );
  }

  group('enrollEmployee', () {
    test('valid → OK with templateCount', () async {
      await setup();
      final r = await bridge.handle(SdkMethods.enrollEmployee, {
        'employeeId': 'EMP-9',
        'name': 'New Hire',
        'department': 'Patrol',
      });
      expect(r.ok, isTrue);
      expect(r.data['templateCount'], 2);
      expect(r.data['poses'], containsAll(['FRONTAL', 'LEFT']));
    });

    test('invalid form → VALIDATION_ERROR with fieldErrors', () async {
      await setup();
      enrollment.formValid = false;
      final r = await bridge.handle(SdkMethods.enrollEmployee,
          {'employeeId': 'EMP-9', 'name': 'X', 'department': 'Y'});
      expect(r.code, SdkCodes.validationError);
      expect((r.data['fieldErrors'] as Map), isNotEmpty);
    });

    test('empty capture → CANCELLED', () async {
      await setup();
      launcher.enrollReturn = {};
      final r = await bridge.handle(SdkMethods.enrollEmployee,
          {'employeeId': 'EMP-9', 'name': 'X', 'department': 'Y'});
      expect(r.code, SdkCodes.cancelled);
    });

    test('missing args → VALIDATION_ERROR', () async {
      await setup();
      final r = await bridge.handle(SdkMethods.enrollEmployee, {'employeeId': 'E'});
      expect(r.code, SdkCodes.validationError);
    });
  });

  group('authenticateEmployee', () {
    test('verified → OK with employeeId + trustScore', () async {
      await setup();
      final r = await bridge.handle(SdkMethods.authenticateEmployee, null);
      expect(r.ok, isTrue);
      expect(r.data['employeeId'], 'EMP-1');
      expect(r.data['trustScore'], 0.93);
    });

    test('rejected → NOT_VERIFIED', () async {
      await setup(auth: _rejected());
      final r = await bridge.handle(SdkMethods.authenticateEmployee, null);
      expect(r.ok, isFalse);
      expect(r.code, SdkCodes.notVerified);
      expect(r.data['verified'], isFalse);
    });
  });

  group('markAttendance', () {
    test('turnstile: first call checkIn, second checkOut', () async {
      await setup();
      final inn = await bridge.handle(SdkMethods.markAttendance, {});
      expect(inn.ok, isTrue);
      expect(inn.data['eventType'], 'checkIn');
      expect(inn.data['attendanceId'], isNotNull);

      final out = await bridge.handle(SdkMethods.markAttendance, {});
      expect(out.ok, isTrue);
      expect(out.data['eventType'], 'checkOut');
    });

    test('not verified → NOT_VERIFIED, nothing marked', () async {
      await setup(auth: _rejected());
      final r = await bridge.handle(SdkMethods.markAttendance, {});
      expect(r.code, SdkCodes.notVerified);
    });

    test('invalid forced value → VALIDATION_ERROR', () async {
      await setup();
      final r = await bridge.handle(SdkMethods.markAttendance, {'forced': 'lunch'});
      expect(r.code, SdkCodes.validationError);
    });
  });

  group('getAttendanceSummary', () {
    test('daily summary returns metrics incl. lateToday + report', () async {
      await setup();
      await bridge.handle(SdkMethods.markAttendance, {}); // create a record
      final r = await bridge.handle(
          SdkMethods.getAttendanceSummary, {'scope': 'daily'});
      expect(r.ok, isTrue);
      final metrics = r.data['metrics'] as Map;
      expect(metrics['presentToday'], 1);
      expect(metrics.containsKey('lateToday'), isTrue);
      expect((r.data['report'] as Map)['type'], 'daily');
    });

    test('monthly scope works', () async {
      await setup();
      final r = await bridge.handle(
          SdkMethods.getAttendanceSummary, {'scope': 'monthly'});
      expect(r.ok, isTrue);
      expect((r.data['report'] as Map)['type'], 'monthly');
    });
  });

  group('syncRecords', () {
    test('offline drain reports skippedOffline; purge included on request', () async {
      await setup();
      await bridge.handle(SdkMethods.markAttendance, {}); // enqueues a pending
      final r = await bridge.handle(SdkMethods.syncRecords, {'purge': true});
      expect(r.ok, isTrue);
      final sync = r.data['sync'] as Map;
      expect(sync['skippedOffline'], greaterThanOrEqualTo(1));
      expect(r.data.containsKey('purge'), isTrue);
    });
  });

  group('dispatch', () {
    test('unknown method → UNKNOWN_METHOD', () async {
      await setup();
      final r = await bridge.handle('frobnicate', {});
      expect(r.code, SdkCodes.unknownMethod);
    });
  });
}
