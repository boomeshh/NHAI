import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/employee_record.dart';
import '../../models/auth_log_entry.dart';
import 'storage_manager_interface.dart';

class StorageManagerImpl implements StorageManagerInterface {
  static const String _employeeBoxName = 'employee_records';
  static const String _logsBoxName = 'auth_logs';
  static const String _aesKeyName = 'nhai_hive_aes_key';
  static const int _maxLogEntries = 1000;

  final FlutterSecureStorage _secureStorage;
  final List<String> _errorBuffer = [];

  Box<String>? _employeeBox;
  Box<String>? _logsBox;

  StorageManagerImpl({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<List<int>> _getOrCreateAesKey() async {
    final existing = await _secureStorage.read(key: _aesKeyName);
    if (existing != null) {
      return base64Decode(existing);
    }
    final key = Hive.generateSecureKey();
    await _secureStorage.write(key: _aesKeyName, value: base64Encode(key));
    return key;
  }

  Future<void> initialize() async {
    await Hive.initFlutter();
    final aesKey = await _getOrCreateAesKey();
    final cipher = HiveAesCipher(aesKey);
    _employeeBox = await Hive.openBox<String>(
      _employeeBoxName,
      encryptionCipher: cipher,
    );
    _logsBox = await Hive.openBox<String>(
      _logsBoxName,
      encryptionCipher: cipher,
    );
  }

  Box<String> get _empBox {
    if (_employeeBox == null) throw StateError('StorageManager not initialized');
    return _employeeBox!;
  }

  Box<String> get _logBox {
    if (_logsBox == null) throw StateError('StorageManager not initialized');
    return _logsBox!;
  }

  @override
  Future<void> saveEmployeeRecord(EmployeeRecord record) async {
    final jsonStr = jsonEncode(record.toJson());
    try {
      await _empBox.put(record.employeeId, jsonStr);
    } catch (e) {
      // Roll back: delete any partial write
      try {
        await _empBox.delete(record.employeeId);
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<EmployeeRecord?> getEmployeeRecord(String employeeId) async {
    final raw = _empBox.get(employeeId);
    if (raw == null) return null;
    return EmployeeRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<List<EmployeeRecord>> getAllEmployeeRecords() async {
    final results = <EmployeeRecord>[];
    for (final key in _empBox.keys) {
      try {
        final raw = _empBox.get(key);
        if (raw != null) {
          results.add(EmployeeRecord.fromJson(
              jsonDecode(raw) as Map<String, dynamic>));
        }
      } catch (e) {
        await logStorageError('Corrupted record for key $key: $e');
      }
    }
    return results;
  }

  @override
  Future<bool> employeeExists(String employeeId) async {
    return _empBox.containsKey(employeeId);
  }

  @override
  Future<void> deleteEmployeeRecord(String employeeId) async {
    await _empBox.delete(employeeId);
  }

  @override
  Future<void> logAuthAttempt(AuthLogEntry entry) async {
    final jsonStr = jsonEncode(entry.toJson());
    await _logBox.add(jsonStr);
    // Rotate: keep at most 1000 entries
    if (_logBox.length > _maxLogEntries) {
      // Delete oldest entries (lowest auto-increment keys)
      final keys = _logBox.keys.toList()..sort();
      final toDelete = keys.take(_logBox.length - _maxLogEntries).toList();
      await _logBox.deleteAll(toDelete);
    }
  }

  @override
  Future<List<AuthLogEntry>> getAuthLogs({int limit = 100}) async {
    final entries = <AuthLogEntry>[];
    for (final key in _logBox.keys) {
      try {
        final raw = _logBox.get(key);
        if (raw != null) {
          entries.add(AuthLogEntry.fromJson(
              jsonDecode(raw) as Map<String, dynamic>));
        }
      } catch (e) {
        await logStorageError('Corrupted log entry for key $key: $e');
      }
    }
    // Sort reverse chronological (most recent first)
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries.take(limit).toList();
  }

  @override
  Future<void> logStorageError(String message) async {
    _errorBuffer.add('[${DateTime.now().toUtc().toIso8601String()}] $message');
  }

  List<String> get errorBuffer => List.unmodifiable(_errorBuffer);
}
