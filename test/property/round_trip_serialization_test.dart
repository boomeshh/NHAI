// Feature: nhai-offline-auth, Property 6: Employee_Record round-trip serialization
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';

void main() {
  group('Property 6: Employee_Record round-trip serialization', () {
    // Helper to generate a random-ish EmployeeRecord for testing
    EmployeeRecord makeRecord({
      String employeeId = 'EMP001',
      String name = 'John Doe',
      String department = 'Engineering',
      List<double>? vector,
      DateTime? enrolledAt,
    }) {
      return EmployeeRecord(
        employeeId: employeeId,
        name: name,
        department: department,
        embedding: FaceEmbedding(vector ?? List.generate(128, (i) => i * 0.01)),
        enrolledAt: (enrolledAt ?? DateTime.utc(2024, 1, 1, 12, 0, 0)),
      );
    }

    test('round-trip: toJson then fromJson produces equal object', () {
      final original = makeRecord();
      final json = original.toJson();
      final restored = EmployeeRecord.fromJson(json);
      expect(restored, equals(original));
    });

    test('round-trip: JSON string encode/decode preserves all fields', () {
      final original = makeRecord(
        employeeId: 'ABC123',
        name: 'Jane Smith',
        department: 'Operations',
        vector: List.generate(128, (i) => (i + 1) * 0.007),
        enrolledAt: DateTime.utc(2025, 6, 15, 8, 30, 0),
      );
      final jsonStr = jsonEncode(original.toJson());
      final restored =
          EmployeeRecord.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      expect(restored.employeeId, equals(original.employeeId));
      expect(restored.name, equals(original.name));
      expect(restored.department, equals(original.department));
      expect(restored.embedding.vector.length, equals(128));
      expect(restored.enrolledAt.isUtc, isTrue);
      expect(
          restored.enrolledAt.isAtSameMomentAs(original.enrolledAt), isTrue);
    });

    test('round-trip: embedding vector values preserved exactly', () {
      final vector = List.generate(128, (i) => i.toDouble() / 128.0);
      final original = makeRecord(vector: vector);
      final restored = EmployeeRecord.fromJson(original.toJson());
      for (int i = 0; i < 128; i++) {
        expect(restored.embedding.vector[i],
            closeTo(original.embedding.vector[i], 1e-10));
      }
    });

    test('round-trip: UTC timestamp preserved across serialization', () {
      final ts = DateTime.utc(2024, 12, 31, 23, 59, 59, 999);
      final original = makeRecord(enrolledAt: ts);
      final restored = EmployeeRecord.fromJson(original.toJson());
      expect(restored.enrolledAt.isUtc, isTrue);
      expect(restored.enrolledAt.millisecondsSinceEpoch,
          equals(original.enrolledAt.millisecondsSinceEpoch));
    });

    test('round-trip: multiple records each serialize independently', () {
      final records = List.generate(
          10,
          (i) => makeRecord(
                employeeId: 'EMP${i.toString().padLeft(3, '0')}',
                name: 'Employee $i',
                vector: List.generate(
                    128, (j) => (i * 128 + j).toDouble() / 10000.0),
              ));
      for (final original in records) {
        final restored = EmployeeRecord.fromJson(original.toJson());
        expect(restored, equals(original));
      }
    });

    // Property-based style: test with varied inputs (100 iterations)
    test('property: round-trip holds for 100 varied EmployeeRecord instances',
        () {
      for (int iter = 0; iter < 100; iter++) {
        final id = 'E${iter.toString().padLeft(4, '0')}';
        final vector =
            List.generate(128, (j) => (iter * 0.001 + j * 0.0001));
        final ts = DateTime.utc(
            2020 + (iter % 5), (iter % 12) + 1, (iter % 28) + 1);
        final original = EmployeeRecord(
          employeeId: id,
          name: 'Name $iter',
          department: 'Dept ${iter % 10}',
          embedding: FaceEmbedding(vector),
          enrolledAt: ts,
        );
        final restored = EmployeeRecord.fromJson(original.toJson());
        expect(restored, equals(original),
            reason: 'Round-trip failed for iteration $iter');
      }
    });
  });
}
