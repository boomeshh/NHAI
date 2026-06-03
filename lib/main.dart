import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'attendance/integration/attendance_module.dart';
import 'attendance/persistence/sqlcipher_database.dart';
import 'core/auth_engine/auth_engine_impl.dart';
import 'core/auth_engine/tflite_model_runner.dart';
import 'core/camera_frame.dart';
import 'core/enrollment_module/enrollment_module_impl.dart';
import 'core/face_detection/mlkit_face_detector.dart';
import 'core/liveness_detector/liveness_detector_impl.dart';
import 'core/recognition/reenrollment_migration.dart';
import 'core/storage_manager/storage_manager_impl.dart';

/// Probes the bundled model to read its real embedding dimension, then purges
/// any stored enrollment whose embedding no longer matches (e.g. after swapping
/// the model file). Those employees must re-enroll with the current model.
/// Safe no-op when the model is unchanged. Never blocks startup.
Future<void> _migrateEnrollmentsForCurrentModel(
    TfliteModelRunner runner, StorageManagerImpl storage) async {
  try {
    await runner.runEmbedding(CameraFrame(
      bytes: List<int>.filled(112 * 112 * 3, 128),
      width: 112,
      height: 112,
      sharpnessScore: 50.0,
    ));
    final dim = runner.embeddingDim;
    final purged =
        await ReEnrollmentMigration(expectedDimension: dim).purgeStale(storage);
    debugPrint(purged.isEmpty
        ? '[Startup] Model embeddingDim=$dim → all enrollments compatible.'
        : '[Startup] Model embeddingDim=$dim → purged ${purged.length} stale '
            'enrollment(s); re-enrollment required: $purged');
  } catch (e) {
    debugPrint('[Startup] Enrollment migration skipped (model probe failed): $e');
  }
}

/// Builds the attendance platform over DURABLE, AES-256 encrypted SQLCipher
/// storage. The DB passphrase is generated once and kept in the hardware-backed
/// keystore (flutter_secure_storage), never alongside the data. If the native
/// database is unavailable for any reason, attendance degrades gracefully to
/// in-memory so it can NEVER block authentication.
Future<AttendanceModule> _buildAttendanceModule(StorageManagerImpl storage) async {
  try {
    const secure = FlutterSecureStorage();
    const keyName = 'nhai_attendance_db_passphrase';
    var passphrase = await secure.read(key: keyName);
    if (passphrase == null) {
      final rng = Random.secure();
      passphrase =
          base64Url.encode(List<int>.generate(32, (_) => rng.nextInt(256)));
      await secure.write(key: keyName, value: passphrase);
    }
    final module = await AttendanceModule.persistent(
      database: SqlCipherDatabase(passphrase: passphrase),
      storage: storage,
    );
    debugPrint('[Startup] Attendance: SQLCipher persistent storage active.');
    return module;
  } catch (e) {
    debugPrint('[Startup] Persistent attendance unavailable ($e) — '
        'falling back to in-memory storage.');
    return AttendanceModule.inMemory(storage: storage);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageManager = StorageManagerImpl();

  try {
    await storageManager.initialize();

    // Real face-recognition pipeline (no demo fallback). If the bundled model
    // is missing or unusable, embedding extraction throws and authentication
    // fails closed — it never fakes success.
    final modelRunner = TfliteModelRunner();
    final faceDetector = MlKitFaceDetector();
    final livenessDetector = LivenessDetectorImpl();

    final authEngine = AuthEngineImpl(
      storage: storageManager,
      livenessDetector: livenessDetector,
      modelRunner: modelRunner,
      // Engine-level blink liveness requires a multi-frame challenge; the auth
      // screen performs liveness using detector landmark frames. Kept false at
      // the single-frame engine layer (enabling it here would reject every user
      // because one frame cannot contain a full blink).
      livenessEnabled: false,
    );
    final enrollmentModule = EnrollmentModuleImpl(
      authEngine: authEngine,
      storage: storageManager,
    );

    // If the model file was swapped (embedding dimension changed), purge
    // incompatible enrollments so users re-enroll with the new model.
    await _migrateEnrollmentsForCurrentModel(modelRunner, storageManager);

    // Attendance platform wiring: durable SQLCipher-encrypted storage (with a
    // safe in-memory fallback), employees bridged from the biometric store.
    final attendanceModule = await _buildAttendanceModule(storageManager);

    runApp(
      NhaiApp(
        storageManager: storageManager,
        authEngine: authEngine,
        enrollmentModule: enrollmentModule,
        faceDetector: faceDetector,
        attendanceModule: attendanceModule,
      ),
    );
  } catch (e) {
    runApp(
      CriticalErrorApp(
        message:
            'Authentication cannot start because the AES key is unavailable. '
            'No enrollment, authentication, or log operation has been opened. '
            'Details: $e',
      ),
    );
  }
}
