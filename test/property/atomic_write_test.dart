// Feature: nhai-offline-auth, Property 8: Employee_Record atomic write — all fields present on retrieval
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';

void main() {
  group('Property 8: Employee_Record atomic write — all fields present on retrieval', () {
    EmployeeRecord makeRecord(int seed) => EmployeeRecord(
          employeeId: 'EMP${seed.toString().padLeft(4, '0')}',
          name: 'Employee $seed',
          department: 'Dept ${seed % 5}',
          embedding: FaceEmbedding(List.generate(128, (j) => (seed * 0.001 + j * 0.0001))),
          enrolledAt: DateTime.utc(2024, (seed % 12) + 1, (seed % 28) + 1),
        );

    test('property: all 5 fields present after round-trip for 100 records', () {
      for (int i = 0; i < 100; i++) {
        final record = makeRecord(i);
        final json = record.toJson();
        final restored = EmployeeRecord.fromJson(json);

        // All 5 fields must be present and non-null
        expect(restored.employeeId, isNotNull);
        expect(restored.name, isNotNull);
        expect(restored.department, isNotNull);
        expect(restored.embedding, isNotNull);
        expect(restored.enrolledAt, isNotNull);

        // Values must match original
        expect(restored.employeeId, equals(record.employeeId));
        expect(restored.name, equals(record.name));
        expect(restored.department, equals(record.department));
        expect(restored.embedding.vector.length, equals(128));
        expect(restored.enrolledAt.isAtSameMomentAs(record.enrolledAt), isTrue);
      }
    });

    test('all fields present for record with minimal values', () {
      final record = EmployeeRecord(
        employeeId: 'A',
        name: 'B',
        department: 'C',
        embedding: FaceEmbedding(List.filled(128, 0.0)),
        enrolledAt: DateTime.utc(2024, 1, 1),
      );
      final restored = EmployeeRecord.fromJson(record.toJson());
      expect(restored.employeeId, equals('A'));
      expect(restored.name, equals('B'));
      expect(restored.department, equals('C'));
      expect(restored.embedding.vector.length, equals(128));
      expect(restored.enrolledAt, isNotNull);
    });
  });
}
