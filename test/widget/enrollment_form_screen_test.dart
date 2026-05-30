import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nhai_auth/ui/screens/enrollment_form_screen.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_interface.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';

/// Widget tests for EnrollmentFormScreen.
///
/// Requirements: 3.1, 3.2, 3.3

// ── Stub implementations ──────────────────────────────────────────────────────

/// A stub [EnrollmentModuleInterface] whose validation behaviour is
/// configurable per test.
class _StubEnrollmentModule implements EnrollmentModuleInterface {
  /// When non-null, [validateForm] returns this result instead of the default.
  ValidationResult? overrideResult;

  @override
  ValidationResult validateForm(
      String employeeId, String name, String department) {
    if (overrideResult != null) return overrideResult!;

    final errors = <String, String>{};
    final trimmedId = employeeId.trim();
    final trimmedName = name.trim();
    final trimmedDept = department.trim();

    if (trimmedId.isEmpty) {
      errors['employeeId'] = 'Employee ID is required.';
    } else if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(trimmedId)) {
      errors['employeeId'] =
          'Employee ID must contain only letters and digits.';
    } else if (trimmedId.length > 20) {
      errors['employeeId'] = 'Employee ID must not exceed 20 characters.';
    }

    if (trimmedName.isEmpty) {
      errors['name'] = 'Name is required.';
    }

    if (trimmedDept.isEmpty) {
      errors['department'] = 'Department is required.';
    }

    return ValidationResult(isValid: errors.isEmpty, fieldErrors: errors);
  }

  @override
  CameraFrame selectBestFrame(List<CameraFrame> frames) => frames.first;

  @override
  Future<EnrollmentResult> enroll(
          EmployeeFormData formData, List<CameraFrame> frames) async =>
      const EnrollmentResult(success: true);
}

/// A stub [StorageManagerInterface] whose [employeeExists] return value is
/// configurable per test.
class _StubStorageManager implements StorageManagerInterface {
  bool existsResult;

  _StubStorageManager({this.existsResult = false});

  @override
  Future<bool> employeeExists(String employeeId) async => existsResult;

  @override
  Future<void> saveEmployeeRecord(EmployeeRecord record) async {}

  @override
  Future<EmployeeRecord?> getEmployeeRecord(String employeeId) async => null;

  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async => [];

  @override
  Future<void> deleteEmployeeRecord(String employeeId) async {}

  @override
  Future<void> logAuthAttempt(AuthLogEntry entry) async {}

  @override
  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async => [];

  @override
  Future<void> logStorageError(String message) async {}
}

// ── Test helpers ──────────────────────────────────────────────────────────────

/// Wraps [EnrollmentFormScreen] in a [MaterialApp] with a stub `/face-capture`
/// route so navigation assertions work correctly.
Widget buildTestApp({
  required _StubEnrollmentModule enrollmentModule,
  required _StubStorageManager storageManager,
}) {
  return MaterialApp(
    initialRoute: '/enroll',
    routes: {
      '/enroll': (_) => EnrollmentFormScreen(
            enrollmentModule: enrollmentModule,
            storageManager: storageManager,
          ),
      '/face-capture': (_) =>
          const Scaffold(body: Text('FaceCaptureScreen')),
    },
  );
}

/// Fills all three form fields with valid values.
Future<void> fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('employee_id_field')), 'EMP001');
  await tester.enterText(find.byKey(const Key('name_field')), 'John Doe');
  await tester.enterText(
      find.byKey(const Key('department_field')), 'Engineering');
}

/// Taps the submit button and pumps the widget tree.
///
/// Uses a pump loop instead of [WidgetTester.pumpAndSettle] because the
/// submit handler is async (calls [StorageManagerInterface.employeeExists])
/// and pumpAndSettle can time out waiting for the microtask queue to drain.
Future<void> tapSubmit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('submit_button')));
  // Pump once to start the async handler.
  await tester.pump();
  // Pump again to let the Future from employeeExists resolve.
  await tester.pump();
  // Final settle for any resulting setState / dialog animation.
  await tester.pump(const Duration(milliseconds: 100));
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('EnrollmentFormScreen — empty field validation (Req 3.1, 3.2)', () {
    testWidgets(
        'submitting with all fields empty shows inline errors on all three fields',
        (tester) async {
      final module = _StubEnrollmentModule();
      final storage = _StubStorageManager();

      await tester.pumpWidget(buildTestApp(
        enrollmentModule: module,
        storageManager: storage,
      ));

      // Tap submit without entering anything.
      await tapSubmit(tester);

      expect(find.text('Employee ID is required.'), findsOneWidget);
      expect(find.text('Name is required.'), findsOneWidget);
      expect(find.text('Department is required.'), findsOneWidget);

      // Must NOT navigate away.
      expect(find.text('FaceCaptureScreen'), findsNothing);
    });

    testWidgets(
        'submitting with only Employee ID filled shows errors for Name and Department',
        (tester) async {
      final module = _StubEnrollmentModule();
      final storage = _StubStorageManager();

      await tester.pumpWidget(buildTestApp(
        enrollmentModule: module,
        storageManager: storage,
      ));

      await tester.enterText(
          find.byKey(const Key('employee_id_field')), 'EMP001');
      await tapSubmit(tester);

      expect(find.text('Name is required.'), findsOneWidget);
      expect(find.text('Department is required.'), findsOneWidget);
      expect(find.text('FaceCaptureScreen'), findsNothing);
    });
  });

  group('EnrollmentFormScreen — invalid Employee ID (Req 3.1, 3.2)', () {
    testWidgets(
        'submitting Employee ID with special characters shows field-level error',
        (tester) async {
      final module = _StubEnrollmentModule();
      final storage = _StubStorageManager();

      await tester.pumpWidget(buildTestApp(
        enrollmentModule: module,
        storageManager: storage,
      ));

      await tester.enterText(
          find.byKey(const Key('employee_id_field')), 'EMP@#\$');
      await tester.enterText(find.byKey(const Key('name_field')), 'John Doe');
      await tester.enterText(
          find.byKey(const Key('department_field')), 'Engineering');
      await tapSubmit(tester);

      expect(
        find.text('Employee ID must contain only letters and digits.'),
        findsOneWidget,
      );
      expect(find.text('FaceCaptureScreen'), findsNothing);
    });
  });

  group('EnrollmentFormScreen — valid submit, no duplicate (Req 3.3)', () {
    testWidgets(
        'submitting a valid form with no duplicate navigates to /face-capture',
        (tester) async {
      final module = _StubEnrollmentModule();
      // existsResult = false → no duplicate
      final storage = _StubStorageManager(existsResult: false);

      await tester.pumpWidget(buildTestApp(
        enrollmentModule: module,
        storageManager: storage,
      ));

      await fillValidForm(tester);
      await tapSubmit(tester);

      expect(find.text('FaceCaptureScreen'), findsOneWidget);
    });
  });

  group('EnrollmentFormScreen — duplicate ID warning dialog (Req 3.3)', () {
    testWidgets(
        'submitting a valid form with a duplicate ID shows the duplicate warning dialog',
        (tester) async {
      final module = _StubEnrollmentModule();
      // existsResult = true → duplicate
      final storage = _StubStorageManager(existsResult: true);

      await tester.pumpWidget(buildTestApp(
        enrollmentModule: module,
        storageManager: storage,
      ));

      await fillValidForm(tester);
      await tapSubmit(tester);

      // The dialog title and content should be visible.
      expect(find.text('Duplicate Record'), findsOneWidget);
      expect(find.textContaining('already exists'), findsOneWidget);

      // Both action buttons must be present.
      expect(find.byKey(const Key('duplicate_dialog_cancel')), findsOneWidget);
      expect(
          find.byKey(const Key('duplicate_dialog_overwrite')), findsOneWidget);
    });

    testWidgets(
        'tapping Cancel in the duplicate dialog stays on the form (no navigation)',
        (tester) async {
      final module = _StubEnrollmentModule();
      final storage = _StubStorageManager(existsResult: true);

      await tester.pumpWidget(buildTestApp(
        enrollmentModule: module,
        storageManager: storage,
      ));

      await fillValidForm(tester);
      await tapSubmit(tester);

      // Dialog is open — tap Cancel.
      await tester.tap(find.byKey(const Key('duplicate_dialog_cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Must remain on the enrollment form.
      expect(find.text('FaceCaptureScreen'), findsNothing);
      // The form fields should still be visible.
      expect(find.byKey(const Key('submit_button')), findsOneWidget);
    });

    testWidgets(
        'tapping Overwrite in the duplicate dialog navigates to /face-capture',
        (tester) async {
      final module = _StubEnrollmentModule();
      final storage = _StubStorageManager(existsResult: true);

      await tester.pumpWidget(buildTestApp(
        enrollmentModule: module,
        storageManager: storage,
      ));

      await fillValidForm(tester);
      await tapSubmit(tester);

      // Dialog is open — tap Overwrite.
      await tester.tap(find.byKey(const Key('duplicate_dialog_overwrite')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('FaceCaptureScreen'), findsOneWidget);
    });
  });
}
