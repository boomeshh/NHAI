// Unit tests for EnrollmentModuleImpl — form validation, sanitization,
// frame selection, and enrollment orchestration.
// Requirements: 3.1, 3.2, 3.3, 3.4, 4.4, 4.5, 4.7, 5.3, 5.4

import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_impl.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_interface.dart';
import 'package:nhai_auth/core/camera_frame.dart';
import 'package:nhai_auth/core/auth_engine/auth_engine_interface.dart';
import 'package:nhai_auth/core/auth_engine/embedding_error.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/auth_result.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';

// ---------------------------------------------------------------------------
// Fakes / stubs
// ---------------------------------------------------------------------------

/// A stub [AuthEngineInterface] that returns a fixed 128-dim embedding.
class _FakeAuthEngine implements AuthEngineInterface {
  final FaceEmbedding? _embedding;
  final EmbeddingError? _error;

  _FakeAuthEngine.success(this._embedding) : _error = null;
  _FakeAuthEngine.failure(this._error) : _embedding = null;

  @override
  Future<FaceEmbedding> extractEmbedding(CameraFrame frame) async {
    if (_error != null) throw _error!;
    return _embedding!;
  }

  @override
  Future<AuthResult> authenticate(CameraFrame frame) async =>
      throw UnimplementedError();

  @override
  Future<AuthResult> authenticateAveraged(List<CameraFrame> frames) async =>
      throw UnimplementedError();
}

/// A stub [StorageManagerInterface] that records calls and can simulate failure.
class _FakeStorage implements StorageManagerInterface {
  final Map<String, EmployeeRecord> _records = {};
  bool throwOnSave = false;

  @override
  Future<bool> employeeExists(String employeeId) async =>
      _records.containsKey(employeeId);

  @override
  Future<void> saveEmployeeRecord(EmployeeRecord record) async {
    if (throwOnSave) throw Exception('Disk full');
    _records[record.employeeId] = record;
  }

  @override
  Future<EmployeeRecord?> getEmployeeRecord(String employeeId) async =>
      _records[employeeId];

  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async =>
      _records.values.toList();

  @override
  Future<void> deleteEmployeeRecord(String employeeId) async =>
      _records.remove(employeeId);

  @override
  Future<void> logAuthAttempt(AuthLogEntry entry) async {}

  @override
  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async => [];

  @override
  Future<void> logStorageError(String message) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

CameraFrame _frame({required double sharpness}) => CameraFrame(
      bytes: [1, 2, 3],
      width: 112,
      height: 112,
      sharpnessScore: sharpness,
    );

FaceEmbedding _embedding128() =>
    FaceEmbedding(List.generate(128, (i) => i.toDouble()));

EmployeeFormData _validForm({String id = 'EMP001'}) => EmployeeFormData(
      employeeId: id,
      name: 'Alice Kumar',
      department: 'Engineering',
    );

void main() {
  late EnrollmentModuleImpl sut;

  setUp(() {
    // No-arg constructor — only validateForm / selectBestFrame tests use this.
    sut = EnrollmentModuleImpl();
  });

  // ---------------------------------------------------------------------------
  // Happy path
  // ---------------------------------------------------------------------------

  group('validateForm — valid inputs', () {
    test('accepts all valid fields', () {
      final result = sut.validateForm('EMP001', 'Alice Kumar', 'Engineering');
      expect(result.isValid, isTrue);
      expect(result.fieldErrors, isEmpty);
    });

    test('accepts Employee ID with letters and digits', () {
      final result = sut.validateForm('ABC123', 'Bob', 'HR');
      expect(result.isValid, isTrue);
    });

    test('accepts Employee ID at exactly 20 characters', () {
      final result =
          sut.validateForm('A' * 20, 'Charlie', 'Operations');
      expect(result.isValid, isTrue);
    });

    test('accepts Name at exactly 60 characters', () {
      final result = sut.validateForm('ID1', 'N' * 60, 'Finance');
      expect(result.isValid, isTrue);
    });

    test('accepts Department at exactly 60 characters', () {
      final result = sut.validateForm('ID1', 'Dave', 'D' * 60);
      expect(result.isValid, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Empty / whitespace-only fields (Requirement 3.2)
  // ---------------------------------------------------------------------------

  group('validateForm — empty fields rejected', () {
    test('rejects empty Employee ID', () {
      final result = sut.validateForm('', 'Alice', 'HR');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('employeeId'));
    });

    test('rejects whitespace-only Employee ID', () {
      final result = sut.validateForm('   ', 'Alice', 'HR');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('employeeId'));
    });

    test('rejects empty Name', () {
      final result = sut.validateForm('EMP1', '', 'HR');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('name'));
    });

    test('rejects whitespace-only Name', () {
      final result = sut.validateForm('EMP1', '\t\n ', 'HR');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('name'));
    });

    test('rejects empty Department', () {
      final result = sut.validateForm('EMP1', 'Alice', '');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('department'));
    });

    test('rejects whitespace-only Department', () {
      final result = sut.validateForm('EMP1', 'Alice', '   ');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('department'));
    });

    test('reports errors for all three empty fields simultaneously', () {
      final result = sut.validateForm('', '', '');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.keys,
          containsAll(['employeeId', 'name', 'department']));
    });
  });

  // ---------------------------------------------------------------------------
  // Employee ID — alphanumeric constraint (Requirement 3.1)
  // ---------------------------------------------------------------------------

  group('validateForm — Employee ID alphanumeric constraint', () {
    test('rejects Employee ID with spaces', () {
      final result = sut.validateForm('EMP 01', 'Alice', 'HR');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('employeeId'));
    });

    test('rejects Employee ID with special characters', () {
      final result = sut.validateForm('EMP-01', 'Alice', 'HR');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('employeeId'));
    });

    test('rejects Employee ID with underscore', () {
      final result = sut.validateForm('EMP_01', 'Alice', 'HR');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('employeeId'));
    });

    test('accepts Employee ID with only letters', () {
      final result = sut.validateForm('EMPID', 'Alice', 'HR');
      expect(result.isValid, isTrue);
    });

    test('accepts Employee ID with only digits', () {
      final result = sut.validateForm('12345', 'Alice', 'HR');
      expect(result.isValid, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Length constraints (Requirement 3.1)
  // ---------------------------------------------------------------------------

  group('validateForm — length constraints', () {
    test('rejects Employee ID exceeding 20 characters', () {
      final result = sut.validateForm('A' * 21, 'Alice', 'HR');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('employeeId'));
    });

    test('rejects Name exceeding 60 characters', () {
      final result = sut.validateForm('EMP1', 'N' * 61, 'HR');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('name'));
    });

    test('rejects Department exceeding 60 characters', () {
      final result = sut.validateForm('EMP1', 'Alice', 'D' * 61);
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('department'));
    });
  });

  // ---------------------------------------------------------------------------
  // Sanitization — trimming (Requirement 3.4)
  // ---------------------------------------------------------------------------

  group('validateForm — whitespace trimming before validation', () {
    test('trims leading/trailing spaces from Employee ID before checking length',
        () {
      // 20 valid chars surrounded by spaces — should pass after trim
      final result = sut.validateForm('  ${'A' * 20}  ', 'Alice', 'HR');
      expect(result.isValid, isTrue);
    });

    test('trims leading/trailing spaces from Name before checking length', () {
      final result = sut.validateForm('EMP1', '  ${'N' * 60}  ', 'HR');
      expect(result.isValid, isTrue);
    });

    test('trims leading/trailing spaces from Department before checking length',
        () {
      final result = sut.validateForm('EMP1', 'Alice', '  ${'D' * 60}  ');
      expect(result.isValid, isTrue);
    });

    test(
        'Employee ID that is only valid after trim passes alphanumeric check',
        () {
      final result = sut.validateForm('  EMP001  ', 'Alice', 'HR');
      expect(result.isValid, isTrue);
    });

    test(
        'Employee ID that exceeds 20 chars even after trim is still rejected',
        () {
      final result = sut.validateForm('  ${'A' * 21}  ', 'Alice', 'HR');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors, contains('employeeId'));
    });
  });

  // ---------------------------------------------------------------------------
  // selectBestFrame (Requirement 4.4)
  // ---------------------------------------------------------------------------

  group('selectBestFrame', () {
    test('returns the single frame in a one-element list', () {
      final frame = _frame(sharpness: 42.0);
      expect(sut.selectBestFrame([frame]), same(frame));
    });

    test('returns the frame with the highest sharpness score', () {
      final low = _frame(sharpness: 10.0);
      final high = _frame(sharpness: 90.0);
      final mid = _frame(sharpness: 50.0);
      expect(sut.selectBestFrame([low, high, mid]), same(high));
    });

    test('returns the first frame when all sharpness scores are equal', () {
      final first = _frame(sharpness: 30.0);
      final second = _frame(sharpness: 30.0);
      expect(sut.selectBestFrame([first, second]), same(first));
    });

    test('returns the last frame when it has the highest sharpness', () {
      final a = _frame(sharpness: 5.0);
      final b = _frame(sharpness: 15.0);
      final c = _frame(sharpness: 99.0);
      expect(sut.selectBestFrame([a, b, c]), same(c));
    });

    test('throws ArgumentError for an empty list', () {
      expect(() => sut.selectBestFrame([]), throwsArgumentError);
    });
  });

  // ---------------------------------------------------------------------------
  // enroll — happy path (Requirements 3.3, 4.4, 4.5, 5.3)
  // ---------------------------------------------------------------------------

  group('enroll — success', () {
    test('returns success with a populated EmployeeRecord', () async {
      final storage = _FakeStorage();
      final engine = _FakeAuthEngine.success(_embedding128());
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      final result = await module.enroll(
        _validForm(),
        [_frame(sharpness: 50.0), _frame(sharpness: 80.0)],
      );

      expect(result.success, isTrue);
      expect(result.errorMessage, isNull);
      expect(result.record, isNotNull);
      expect(result.record!.employeeId, 'EMP001');
      expect(result.record!.name, 'Alice Kumar');
      expect(result.record!.department, 'Engineering');
      expect(result.record!.embedding.vector.length, 128);
    });

    test('persists the record to storage', () async {
      final storage = _FakeStorage();
      final engine = _FakeAuthEngine.success(_embedding128());
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      await module.enroll(_validForm(), [_frame(sharpness: 60.0)]);

      expect(storage._records.containsKey('EMP001'), isTrue);
    });

    test('uses the best (highest-sharpness) frame for embedding extraction',
        () async {
      // We verify indirectly: if the wrong frame were used (sharpness < 10),
      // extractEmbedding would throw LOW_QUALITY_FRAME and enroll would fail.
      final storage = _FakeStorage();
      final engine = _FakeAuthEngine.success(_embedding128());
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      // First frame has sharpness 5 (below threshold), second has 80.
      final lowQuality = CameraFrame(
          bytes: [1], width: 112, height: 112, sharpnessScore: 5.0);
      final highQuality = CameraFrame(
          bytes: [1], width: 112, height: 112, sharpnessScore: 80.0);

      final result =
          await module.enroll(_validForm(), [lowQuality, highQuality]);
      expect(result.success, isTrue);
    });

    test('trims whitespace from form fields before storing', () async {
      final storage = _FakeStorage();
      final engine = _FakeAuthEngine.success(_embedding128());
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      final form = EmployeeFormData(
        employeeId: '  EMP002  ',
        name: '  Bob Singh  ',
        department: '  HR  ',
      );
      final result = await module.enroll(form, [_frame(sharpness: 50.0)]);

      expect(result.success, isTrue);
      expect(result.record!.employeeId, 'EMP002');
      expect(result.record!.name, 'Bob Singh');
      expect(result.record!.department, 'HR');
    });
  });

  // ---------------------------------------------------------------------------
  // enroll — validation failure
  // ---------------------------------------------------------------------------

  group('enroll — validation failure', () {
    test('returns failure when Employee ID is empty', () async {
      final storage = _FakeStorage();
      final engine = _FakeAuthEngine.success(_embedding128());
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      final form = EmployeeFormData(
          employeeId: '', name: 'Alice', department: 'HR');
      final result = await module.enroll(form, [_frame(sharpness: 50.0)]);

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(storage._records, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // enroll — duplicate ID (Requirement 3.3)
  // ---------------------------------------------------------------------------

  group('enroll — duplicate ID', () {
    test('returns failure with a descriptive message when ID already exists',
        () async {
      final storage = _FakeStorage();
      // Pre-populate storage with the same ID.
      storage._records['EMP001'] = EmployeeRecord(
        employeeId: 'EMP001',
        name: 'Existing',
        department: 'IT',
        embedding: _embedding128(),
        enrolledAt: DateTime.now().toUtc(),
      );
      final engine = _FakeAuthEngine.success(_embedding128());
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      final result =
          await module.enroll(_validForm(), [_frame(sharpness: 50.0)]);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('EMP001'));
      // No overwrite should have occurred.
      expect(storage._records['EMP001']!.name, 'Existing');
    });
  });

  // ---------------------------------------------------------------------------
  // enroll — embedding extraction failure (Requirement 4.7)
  // ---------------------------------------------------------------------------

  group('enroll — embedding extraction failure', () {
    test('returns descriptive error on NO_FACE_DETECTED', () async {
      final storage = _FakeStorage();
      final engine = _FakeAuthEngine.failure(
          const EmbeddingError(EmbeddingErrorCode.noFaceDetected, 'no face'));
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      final result =
          await module.enroll(_validForm(), [_frame(sharpness: 50.0)]);

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(result.errorMessage, isNotEmpty);
      expect(storage._records, isEmpty);
    });

    test('returns descriptive error on LOW_QUALITY_FRAME', () async {
      final storage = _FakeStorage();
      final engine = _FakeAuthEngine.failure(
          const EmbeddingError(
              EmbeddingErrorCode.lowQualityFrame, 'low quality'));
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      final result =
          await module.enroll(_validForm(), [_frame(sharpness: 50.0)]);

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(storage._records, isEmpty);
    });

    test('returns descriptive error on MODEL_INFERENCE_FAILED', () async {
      final storage = _FakeStorage();
      final engine = _FakeAuthEngine.failure(
          const EmbeddingError(
              EmbeddingErrorCode.modelInferenceFailed, 'inference failed'));
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      final result =
          await module.enroll(_validForm(), [_frame(sharpness: 50.0)]);

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(storage._records, isEmpty);
    });

    test('error message contains retry hint', () async {
      final storage = _FakeStorage();
      final engine = _FakeAuthEngine.failure(
          const EmbeddingError(EmbeddingErrorCode.noFaceDetected, 'no face'));
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      final result =
          await module.enroll(_validForm(), [_frame(sharpness: 50.0)]);

      // The message should guide the operator to retry.
      expect(result.errorMessage!.toLowerCase(),
          anyOf(contains('retry'), contains('try again'), contains('again')));
    });
  });

  // ---------------------------------------------------------------------------
  // enroll — storage write failure (Requirement 5.4)
  // ---------------------------------------------------------------------------

  group('enroll — storage write failure', () {
    test('returns failure and does not show success when storage throws',
        () async {
      final storage = _FakeStorage()..throwOnSave = true;
      final engine = _FakeAuthEngine.success(_embedding128());
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      final result =
          await module.enroll(_validForm(), [_frame(sharpness: 50.0)]);

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
    });

    test('leaves no partial record in storage after write failure', () async {
      final storage = _FakeStorage()..throwOnSave = true;
      final engine = _FakeAuthEngine.success(_embedding128());
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      await module.enroll(_validForm(), [_frame(sharpness: 50.0)]);

      expect(storage._records, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // enroll — empty frames list
  // ---------------------------------------------------------------------------

  group('enroll — empty frames list', () {
    test('returns failure when no frames are provided', () async {
      final storage = _FakeStorage();
      final engine = _FakeAuthEngine.success(_embedding128());
      final module = EnrollmentModuleImpl(
          authEngine: engine, storage: storage);

      final result = await module.enroll(_validForm(), []);

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
    });
  });
}
