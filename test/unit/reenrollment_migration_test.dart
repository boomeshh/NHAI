import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/recognition/embedding_math.dart';
import 'package:nhai_auth/core/recognition/reenrollment_migration.dart';
import 'package:nhai_auth/core/storage_manager/storage_manager_interface.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/employee_record.dart';
import 'package:nhai_auth/models/face_embedding.dart';

class _Storage implements StorageManagerInterface {
  final Map<String, EmployeeRecord> records = {};
  @override
  Future<void> saveEmployeeRecord(EmployeeRecord r) async =>
      records[r.employeeId] = r;
  @override
  Future<EmployeeRecord?> getEmployeeRecord(String id) async => records[id];
  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async =>
      records.values.toList();
  @override
  Future<bool> employeeExists(String id) async => records.containsKey(id);
  @override
  Future<void> deleteEmployeeRecord(String id) async => records.remove(id);
  @override
  Future<void> logAuthAttempt(AuthLogEntry e) async {}
  @override
  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async => [];
  @override
  Future<void> logStorageError(String m) async {}
}

EmployeeRecord _rec(String id, List<double> v) => EmployeeRecord(
      employeeId: id,
      name: id,
      department: 'D',
      embedding: FaceEmbedding(v),
      enrolledAt: DateTime.utc(2026, 1, 1),
    );

List<double> _unit(int dim, double seed) {
  final v = List<double>.generate(dim, (i) => (i + seed) % 5 - 2.0);
  return EmbeddingMath.l2Normalize(v);
}

void main() {
  const migration = ReEnrollmentMigration(expectedDimension: 192);

  test('modern templates (192-d, unit magnitude) are NOT stale', () async {
    final s = _Storage();
    await s.saveEmployeeRecord(_rec('OK1', _unit(192, 1)));
    await s.saveEmployeeRecord(_rec('OK2', _unit(192, 2)));
    expect(await migration.scan(s), isEmpty);
  });

  test('wrong-dimension template (legacy 128-d model) is flagged stale',
      () async {
    final s = _Storage();
    await s.saveEmployeeRecord(_rec('OLD128', _unit(128, 1)));
    final stale = await migration.scan(s);
    expect(stale, hasLength(1));
    expect(stale.first.employeeId, 'OLD128');
    expect(stale.first.storedLength, 128);
    expect(stale.first.reason, contains('dimension'));
  });

  test('non-normalized template (pre-alignment pipeline) is flagged stale',
      () async {
    final s = _Storage();
    // 192-d but raw (magnitude far from 1.0) → legacy pipeline.
    await s.saveEmployeeRecord(
        _rec('RAW', List<double>.generate(192, (i) => (i % 7) + 3.0)));
    final stale = await migration.scan(s);
    expect(stale, hasLength(1));
    expect(stale.first.reason, contains('normaliz'));
    expect(stale.first.storedMagnitude, greaterThan(1.5));
  });

  test('purgeStale removes only stale templates, keeps modern ones', () async {
    final s = _Storage();
    await s.saveEmployeeRecord(_rec('MODERN', _unit(192, 1)));
    await s.saveEmployeeRecord(_rec('LEGACY', _unit(128, 1)));
    await s.saveEmployeeRecord(
        _rec('RAW', List<double>.generate(192, (i) => 9.0)));

    final purged = await migration.purgeStale(s);
    expect(purged.toSet(), {'LEGACY', 'RAW'});
    final remaining = await s.getAllEmployeeRecords();
    expect(remaining.map((r) => r.employeeId).toList(), ['MODERN']);
  });

  test('magnitude of a unit vector is ~1.0 (sanity)', () {
    expect(EmbeddingMath.magnitude(_unit(192, 3)), closeTo(1.0, 1e-9));
    expect(math.sqrt(192), greaterThan(0)); // dim sanity
  });
}
