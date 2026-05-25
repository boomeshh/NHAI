import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';

void main() {
  group('EmployeeRecord serialization edge cases', () {
    test('embedding vector length is exactly 128', () {
      final record = EmployeeRecord(
        employeeId: 'EMP001',
        name: 'Test',
        department: 'IT',
        embedding: FaceEmbedding(List.generate(128, (i) => i.toDouble())),
        enrolledAt: DateTime.utc(2024, 1, 1),
      );
      final restored = EmployeeRecord.fromJson(record.toJson());
      expect(restored.embedding.vector.length, equals(128));
    });

    test('enrolledAt is always stored and restored as UTC', () {
      final localTime = DateTime(2024, 6, 15, 10, 30, 0); // local time
      final record = EmployeeRecord(
        employeeId: 'EMP002',
        name: 'UTC Test',
        department: 'Ops',
        embedding: FaceEmbedding(List.filled(128, 0.5)),
        enrolledAt: localTime.toUtc(),
      );
      final restored = EmployeeRecord.fromJson(record.toJson());
      expect(restored.enrolledAt.isUtc, isTrue);
    });

    test('fromJson throws on missing required field', () {
      final json = {
        'employeeId': 'EMP003',
        // 'name' is missing
        'department': 'HR',
        'embedding': {'vector': List.filled(128, 0.0)},
        'enrolledAt': '2024-01-01T00:00:00.000Z',
      };
      expect(() => EmployeeRecord.fromJson(json), throwsA(anything));
    });

    test('FaceEmbedding equality works correctly', () {
      final v = List.generate(128, (i) => i.toDouble());
      final e1 = FaceEmbedding(v);
      final e2 = FaceEmbedding(List.from(v));
      expect(e1, equals(e2));
    });

    test('FaceEmbedding inequality on different vectors', () {
      final e1 = FaceEmbedding(List.filled(128, 0.0));
      final e2 = FaceEmbedding(List.filled(128, 1.0));
      expect(e1, isNot(equals(e2)));
    });
  });

  group('AuthLogEntry serialization', () {
    test('round-trip preserves all fields including nullables', () {
      final entry = AuthLogEntry(
        id: 'test-uuid-1234',
        timestamp: DateTime.utc(2024, 3, 15, 9, 0, 0),
        result: AuthClassification.verified,
        trustScore: 0.92,
        employeeId: 'EMP001',
        failureReason: null,
      );
      final restored = AuthLogEntry.fromJson(entry.toJson());
      expect(restored.id, equals(entry.id));
      expect(restored.result, equals(AuthClassification.verified));
      expect(restored.trustScore, closeTo(0.92, 1e-10));
      expect(restored.employeeId, equals('EMP001'));
      expect(restored.failureReason, isNull);
    });

    test('round-trip for FAILED entry with failure reason', () {
      final entry = AuthLogEntry(
        id: 'test-uuid-5678',
        timestamp: DateTime.utc(2024, 3, 15, 9, 5, 0),
        result: AuthClassification.failed,
        trustScore: 0.42,
        employeeId: null,
        failureReason: 'Face not recognized',
      );
      final restored = AuthLogEntry.fromJson(entry.toJson());
      expect(restored.result, equals(AuthClassification.failed));
      expect(restored.employeeId, isNull);
      expect(restored.failureReason, equals('Face not recognized'));
    });

    test('timestamp is UTC after round-trip', () {
      final entry = AuthLogEntry(
        id: 'uuid-ts-test',
        timestamp: DateTime.utc(2025, 1, 1, 0, 0, 0),
        result: AuthClassification.failed,
        trustScore: 0.0,
      );
      final restored = AuthLogEntry.fromJson(entry.toJson());
      expect(restored.timestamp.isUtc, isTrue);
    });
  });
}
