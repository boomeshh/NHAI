// Device-only SQLCipher (AES-256) implementation of [SecureDatabase].
//
// The whole database file is encrypted at rest with a passphrase that the
// caller sources from flutter_secure_storage (hardware-backed keystore). Each
// logical table stores one JSON document per row: (id TEXT PRIMARY KEY,
// json TEXT). Repositories deserialize via the models' fromJson factories.
//
// This file imports the native plugin and therefore must never be instantiated
// in unit tests (which use InMemorySecureDatabase). It still compiles under the
// VM test runner — the plugin's platform channel is simply never invoked.
library;

import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import 'secure_database.dart';

class SqlCipherDatabase implements SecureDatabase {
  /// AES passphrase. Caller fetches/derives this from secure storage; it is
  /// never persisted in plaintext alongside the data.
  final String passphrase;
  final String databaseName;
  final int version;

  Database? _db;

  SqlCipherDatabase({
    required this.passphrase,
    this.databaseName = 'nhai_attendance.db',
    this.version = 1,
  });

  Database get _require {
    final db = _db;
    if (db == null) {
      throw StateError('SqlCipherDatabase.init() must be called before use');
    }
    return db;
  }

  @override
  Future<void> init() async {
    if (_db != null) return;
    final dir = await getDatabasesPath();
    final path = '$dir/$databaseName';
    _db = await openDatabase(
      path,
      password: passphrase,
      version: version,
      onCreate: (db, _) async {
        for (final table in AttendanceTables.all) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS $table ('
            'id TEXT PRIMARY KEY, json TEXT NOT NULL)',
          );
        }
      },
    );
  }

  @override
  Future<void> put(String table, String id, Map<String, dynamic> json) async {
    await _require.insert(
      table,
      {'id': id, 'json': jsonEncode(json)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Map<String, dynamic>?> get(String table, String id) async {
    final rows = await _require
        .query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _decode(rows.first);
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String table) async {
    final rows = await _require.query(table);
    return rows.map(_decode).toList();
  }

  @override
  Future<void> delete(String table, String id) async {
    await _require.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<int> deleteWhereIdIn(String table, Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return 0;
    final placeholders = List.filled(list.length, '?').join(',');
    return _require
        .delete(table, where: 'id IN ($placeholders)', whereArgs: list);
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Map<String, dynamic> _decode(Map<String, Object?> row) =>
      jsonDecode(row['json'] as String) as Map<String, dynamic>;
}
