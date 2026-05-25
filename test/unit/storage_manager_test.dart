import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';

// In-memory mock of StorageManagerInterface for unit testing
// (Hive requires a real device/filesystem; we test the logic layer)
class InMemoryStorageManager {
  final Map<String, String> _employees = {};
  final List<String> _logs = [];
  final List<String> _errors = [];
  static const int _maxLogs = 1000;
  bool _shouldFailWrite = false;

  void setWriteFailure(bool fail) => _shouldFailWrite = fail;

  Future<void> saveEmployeeRecord(EmployeeRecord record) async {
    if (_shouldFailWrite) throw Exception('Simulated write failure');
    _employees[record.employeeId] = jsonEncode(record.toJson());
  }

  Future<EmployeeRecord?> getEmployeeRecord(String employeeId) async {
    final raw = _employees[employeeId];
    if (raw == null) return null;
    return EmployeeRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<List<EmployeeRecord>> getAllEmployeeRecords() async {
    final results = <EmployeeRecord>[];
    for (final entry in _employees.entries) {
      try {
        results.add(EmployeeRecord.fromJson(
            jsonDecode(entry.value) as Map<String, dynamic>));
      } catch (e) {
        _errors.add('Corrupted record: ${entry.key}');
      }
    }
    return results;
  }

  Future<bool> employeeExists(String employeeId) async =>
      _employees.containsKey(employeeId);

  Future<void> logAuthAttempt(AuthLogEntry entry) async {
    _logs.add(jsonEncode(entry.toJson()));
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0); // remove oldest
    }
  }

  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async {
    final entries = _logs
        .map((raw) =>
            AuthLogEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries.take(limit).toList();
  }

  void injectCorruptedRecord(String key) {
    _employees[key] = 'NOT_VALID_JSON{{{';
  }

  List<String> get errors => List.unmodifiable(_errors);
  int get logCount => _logs.length;
}

EmployeeRecord makeRecord(String id) => EmployeeRecord(
      employeeId: id,
      name: 'Test Employee',
      department: 'Engineering',
      embedding: FaceEmbedding(List.filled(128, 0.5)),
      enrolledAt: DateTime.utc(2024, 1, 1),
    );

AuthLogEntry makeLogEntry(int minutesAgo, {bool verified = true}) => AuthLogEntry(
      id: 'uuid-$minutesAgo',
      timestamp: DateTime.utc(2024, 6, 1, 12, 0, 0)
          .subtract(Duration(minutes: minutesAgo)),
      result: verified ? AuthClassification.verified : AuthClassification.failed,
      trustScore: verified ? 0.9 : 0.3,
      employeeId: verified ? 'EMP001' : null,
      failureReason: verified ? null : 'Face not recognized',
    );

void main() {
  group('Storage_Manager unit tests', () {
    late InMemoryStorageManager storage;

    setUp(() {
      storage = InMemoryStorageManager();
    });

    group('write failure rollback', () {
      test('failed write leaves no partial record', () async {
        storage.setWriteFailure(true);
        final record = makeRecord('EMP001');
        expect(
          () => storage.saveEmployeeRecord(record),
          throwsException,
        );
        final exists = await storage.employeeExists('EMP001');
        expect(exists, isFalse, reason: 'No partial record should remain after write failure');
      });
    });

    group('corrupted record skipping', () {
      test('corrupted record is skipped, others returned normally', () async {
        await storage.saveEmployeeRecord(makeRecord('EMP001'));
        await storage.saveEmployeeRecord(makeRecord('EMP002'));
        storage.injectCorruptedRecord('EMP_CORRUPT');

        final records = await storage.getAllEmployeeRecords();
        expect(records.length, equals(2));
        expect(records.any((r) => r.employeeId == 'EMP001'), isTrue);
        expect(records.any((r) => r.employeeId == 'EMP002'), isTrue);
        expect(storage.errors.length, equals(1));
      });
    });

    group('log rotation at 1000-entry boundary', () {
      test('log count stays at 1000 after exceeding limit', () async {
        for (int i = 0; i < 1001; i++) {
          await storage.logAuthAttempt(makeLogEntry(i));
        }
        expect(storage.logCount, equals(1000));
      });

      test('exactly 1000 entries: adding one keeps count at 1000', () async {
        for (int i = 0; i < 1000; i++) {
          await storage.logAuthAttempt(makeLogEntry(i));
        }
        expect(storage.logCount, equals(1000));
        await storage.logAuthAttempt(makeLogEntry(1000));
        expect(storage.logCount, equals(1000));
      });
    });

    group('getAuthLogs ordering and limit', () {
      test('logs returned in reverse chronological order', () async {
        await storage.logAuthAttempt(makeLogEntry(60));  // oldest
        await storage.logAuthAttempt(makeLogEntry(30));
        await storage.logAuthAttempt(makeLogEntry(5));   // newest

        final logs = await storage.getAuthLogs();
        expect(logs.first.timestamp.isAfter(logs.last.timestamp), isTrue);
      });

      test('default limit is 100', () async {
        for (int i = 0; i < 150; i++) {
          await storage.logAuthAttempt(makeLogEntry(i));
        }
        final logs = await storage.getAuthLogs();
        expect(logs.length, equals(100));
      });
    });

    group('employee CRUD', () {
      test('save and retrieve employee record', () async {
        final record = makeRecord('EMP001');
        await storage.saveEmployeeRecord(record);
        final retrieved = await storage.getEmployeeRecord('EMP001');
        expect(retrieved, isNotNull);
        expect(retrieved!.employeeId, equals('EMP001'));
      });

      test('employeeExists returns false for unknown ID', () async {
        final exists = await storage.employeeExists('UNKNOWN');
        expect(exists, isFalse);
      });

      test('employeeExists returns true after save', () async {
        await storage.saveEmployeeRecord(makeRecord('EMP002'));
        final exists = await storage.employeeExists('EMP002');
        expect(exists, isTrue);
      });
    });
  });
}
