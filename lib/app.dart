import 'package:flutter/material.dart';

import 'core/auth_engine/auth_engine_interface.dart';
import 'core/enrollment_module/enrollment_module_interface.dart';
import 'core/face_detection/face_detector_interface.dart';
import 'core/storage_manager/storage_manager_interface.dart';
import 'ui/screens/authentication_screen.dart' as auth_screen;
import 'ui/screens/enrollment_form_screen.dart';
import 'ui/screens/face_capture_screen.dart' as face_capture;
import 'ui/screens/home_screen.dart';
import 'ui/screens/local_logs_screen.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/verification_result_screen.dart';

class NhaiApp extends StatelessWidget {
  final StorageManagerInterface storageManager;
  final AuthEngineInterface authEngine;
  final EnrollmentModuleInterface enrollmentModule;
  final String initialRoute;
  final face_capture.FrameProvider? faceCaptureFrameProvider;
  final auth_screen.FrameProvider? authFrameProvider;
  final int faceCaptureMinFrameCount;
  final Duration faceCaptureNoFaceTimeout;

  /// Real face detector (ML Kit) used by the camera screens. Null in tests,
  /// which inject synthetic frames via the frame providers instead.
  final FaceDetectorInterface? faceDetector;

  const NhaiApp({
    super.key,
    required this.storageManager,
    required this.authEngine,
    required this.enrollmentModule,
    this.initialRoute = '/',
    this.faceCaptureFrameProvider,
    this.authFrameProvider,
    this.faceCaptureMinFrameCount = 3,
    this.faceCaptureNoFaceTimeout = const Duration(seconds: 10),
    this.faceDetector,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NHAI Offline Authentication',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003580),
          primary: const Color(0xFF003580),
          secondary: const Color(0xFFFF6600),
        ),
        useMaterial3: true,
      ),
      initialRoute: initialRoute,
      routes: {
        '/': (_) => const SplashScreen(),
        '/home': (_) => const HomeScreen(),
        '/enroll': (_) => EnrollmentFormScreen(
              enrollmentModule: enrollmentModule,
              storageManager: storageManager,
            ),
        '/face-capture': (_) => face_capture.FaceCaptureScreen(
              enrollmentModule: enrollmentModule,
              frameProvider: faceCaptureFrameProvider,
              minFrameCount: faceCaptureMinFrameCount,
              noFaceTimeout: faceCaptureNoFaceTimeout,
              faceDetector: faceDetector,
            ),
        '/authenticate': (_) => auth_screen.AuthenticationScreen(
              authEngine: authEngine,
              frameProvider: authFrameProvider,
              faceDetector: faceDetector,
            ),
        '/verification-result': (_) => VerificationResultScreen(
              storageManager: storageManager,
            ),
        '/logs': (_) => LocalLogsScreen(
              storageManager: storageManager,
            ),
      },
    );
  }
}

class CriticalErrorApp extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const CriticalErrorApp({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NHAI Offline Authentication',
      debugShowCheckedModeBanner: false,
      home: CriticalErrorScreen(
        message: message,
        onRetry: onRetry,
      ),
    );
  }
}

class CriticalErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _failedRed = Color(0xFFC62828);

  const CriticalErrorScreen({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('critical_error_screen'),
      backgroundColor: _deepBlue,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _failedRed.withValues(alpha: 0.15),
                    border: const Border.fromBorderSide(
                      BorderSide(color: _failedRed, width: 3),
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: _failedRed,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Secure Storage Unavailable',
                  key: Key('critical_error_headline'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  key: const Key('critical_error_message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _white.withValues(alpha: 0.74),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    key: const Key('critical_error_retry_button'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _saffron,
                      foregroundColor: _white,
                      minimumSize: const Size(160, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
