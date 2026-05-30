import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/auth_engine/auth_engine_impl.dart';
import 'core/auth_engine/tflite_model_runner.dart';
import 'core/enrollment_module/enrollment_module_impl.dart';
import 'core/face_detection/mlkit_face_detector.dart';
import 'core/liveness_detector/liveness_detector_impl.dart';
import 'core/storage_manager/storage_manager_impl.dart';

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

    runApp(
      NhaiApp(
        storageManager: storageManager,
        authEngine: authEngine,
        enrollmentModule: enrollmentModule,
        faceDetector: faceDetector,
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
