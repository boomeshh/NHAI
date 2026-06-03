import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../../core/camera_frame.dart';
import '../../core/face_detection/detection_forensics.dart';
import '../../core/face_detection/face_detector_interface.dart';
import '../../core/face_detection/face_quality.dart';
import '../../core/face_detection/face_stability_tracker.dart';
import '../../core/face_detection/landmark_audit.dart';
import '../../core/face_preprocessor.dart';
import '../../core/validation/biometric_validation.dart';

/// One frame's raw detection signals, consumed by the validation screen.
///
/// On-device these are produced from the camera + ML Kit; in tests a synthetic
/// stream of these is injected so the whole dashboard can be exercised without
/// a physical camera.
class FaceDetectionSample {
  final int faceCount;
  final double brightness;
  final double sharpness;
  final int boxLeft, boxTop, boxWidth, boxHeight;
  final int frameWidth, frameHeight;
  final double yaw, pitch, roll;
  final double leftEyeOpen, rightEyeOpen;
  final bool hasLeftEye, hasRightEye, hasNose, hasMouthLeft, hasMouthRight;

  const FaceDetectionSample({
    required this.faceCount,
    required this.brightness,
    required this.sharpness,
    required this.boxLeft,
    required this.boxTop,
    required this.boxWidth,
    required this.boxHeight,
    required this.frameWidth,
    required this.frameHeight,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.leftEyeOpen,
    required this.rightEyeOpen,
    required this.hasLeftEye,
    required this.hasRightEye,
    required this.hasNose,
    required this.hasMouthLeft,
    required this.hasMouthRight,
  });
}

typedef SampleProvider = Stream<FaceDetectionSample> Function();

/// Face Detection Validation Screen (Phase 6).
///
/// Live device tool that surfaces every detection-quality signal — FPS, face
/// count, head pose, brightness, sharpness, quality score, stable-frame count,
/// blink state — and shows GREEN when the current frame is accepted, RED when
/// it is rejected (with the reason). Read-only diagnostics: it never enrolls,
/// authenticates, or touches the recognition engine.
class FaceDetectionValidationScreen extends StatefulWidget {
  /// Real detector for the device path. Null in tests (use [sampleProvider]).
  final FaceDetectorInterface? faceDetector;

  /// Injected synthetic sample source for tests. When null the screen uses the
  /// real front camera + [faceDetector].
  final SampleProvider? sampleProvider;

  final QualityThresholds thresholds;
  final int requiredStableFrames;

  const FaceDetectionValidationScreen({
    super.key,
    this.faceDetector,
    this.sampleProvider,
    this.thresholds = QualityThresholds.standard,
    this.requiredStableFrames = 5,
  });

  @override
  State<FaceDetectionValidationScreen> createState() =>
      _FaceDetectionValidationScreenState();
}

class _FaceDetectionValidationScreenState
    extends State<FaceDetectionValidationScreen> {
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _green = Color(0xFF2E7D32);
  static const Color _red = Color(0xFFC62828);

  late final FaceQualityAnalyzer _analyzer =
      FaceQualityAnalyzer(t: widget.thresholds);
  static const LandmarkAuditor _auditor = LandmarkAuditor();
  late final FaceStabilityTracker _stability =
      FaceStabilityTracker(requiredConsecutive: widget.requiredStableFrames);
  final BlinkLivenessTracker _blink = BlinkLivenessTracker();

  StreamSubscription<FaceDetectionSample>? _sub;
  CameraController? _camera;
  CameraDescription? _cameraDescription;
  bool _detecting = false;
  String? _error;

  // FPS measurement (wall-clock between frames).
  final Stopwatch _clock = Stopwatch()..start();
  int _lastFrameMs = 0;
  double _fps = 0;

  // Latest computed state for the dashboard.
  int _faceCount = 0;
  FaceQualityScore? _quality;
  LandmarkAuditResult? _audit;
  StabilityReading? _stab;
  double _brightness = 0, _sharpness = 0;
  double _yaw = 0, _pitch = 0, _roll = 0;
  bool _blinkDetected = false;

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    if (widget.sampleProvider != null) {
      _sub = widget.sampleProvider!().listen(_onSample);
    } else {
      _initCamera();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (widget.faceDetector == null) {
      setState(() => _error = 'No camera/detector available');
      return;
    }
    try {
      final cams = await availableCameras();
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(front, ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _camera = ctrl;
        _cameraDescription = front;
      });
      ctrl.startImageStream(_handleImage);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera init failed: $e');
    }
  }

  int _rotationDegrees() {
    final cam = _cameraDescription;
    final ctrl = _camera;
    if (cam == null || ctrl == null) return 0;
    final comp = _orientations[ctrl.value.deviceOrientation] ?? 0;
    return cam.lensDirection == CameraLensDirection.front
        ? (cam.sensorOrientation + comp) % 360
        : (cam.sensorOrientation - comp + 360) % 360;
  }

  Future<void> _handleImage(CameraImage image) async {
    if (_detecting) return;
    final detector = widget.faceDetector;
    if (detector == null) return;
    _detecting = true;
    try {
      final p = image.planes.first;
      final double brightness =
          FaceQualityAnalyzer.brightnessFromLuma(p.bytes);
      final double sharpness = FaceQualityAnalyzer.laplacianVariance(
          p.bytes, image.width, image.height);
      final rgb = FacePreprocessor.nv21ToRgb(p.bytes, image.width, image.height,
          bytesPerRow: p.bytesPerRow);
      final base = CameraFrame(
        bytes: p.bytes,
        width: image.width,
        height: image.height,
        sharpnessScore: sharpness,
        rgbBytes: rgb,
        nv21Bytes: p.bytes,
        nv21BytesPerRow: p.bytesPerRow,
        rotationDegrees: _rotationDegrees(),
      );
      final faces = await detector.detect(base);
      if (!mounted) return;
      if (faces.length != 1) {
        _onSample(FaceDetectionSample(
          faceCount: faces.length,
          brightness: brightness,
          sharpness: sharpness,
          boxLeft: 0, boxTop: 0, boxWidth: 0, boxHeight: 0,
          frameWidth: image.width, frameHeight: image.height,
          yaw: 0, pitch: 0, roll: 0,
          leftEyeOpen: 0, rightEyeOpen: 0,
          hasLeftEye: false, hasRightEye: false, hasNose: false,
          hasMouthLeft: false, hasMouthRight: false,
        ));
        return;
      }
      final f = faces.first;
      _onSample(FaceDetectionSample(
        faceCount: 1,
        brightness: brightness,
        sharpness: sharpness,
        boxLeft: f.box.left,
        boxTop: f.box.top,
        boxWidth: f.box.width,
        boxHeight: f.box.height,
        frameWidth: image.width,
        frameHeight: image.height,
        yaw: f.headEulerAngleY ?? 0,
        pitch: f.headEulerAngleX ?? 0,
        roll: f.headEulerAngleZ ?? 0,
        leftEyeOpen: f.leftEyeOpenProbability ?? 1.0,
        rightEyeOpen: f.rightEyeOpenProbability ?? 1.0,
        hasLeftEye: f.hasLeftEye,
        hasRightEye: f.hasRightEye,
        hasNose: f.hasNoseBase,
        hasMouthLeft: f.mouthLeftPosition != null,
        hasMouthRight: f.mouthRightPosition != null,
      ));
    } catch (e) {
      debugPrint('[FaceDetectionValidation] $e');
    } finally {
      _detecting = false;
    }
  }

  void _onSample(FaceDetectionSample s) {
    // FPS from inter-frame interval.
    final int now = _clock.elapsedMilliseconds;
    final int dt = now - _lastFrameMs;
    _lastFrameMs = now;
    if (dt > 0) _fps = 1000.0 / dt;

    final bool single = s.faceCount == 1;
    final quality = _analyzer.analyze(QualityInput(
      faceDetected: single,
      brightness: s.brightness,
      sharpness: s.sharpness,
      boxWidth: s.boxWidth,
      boxHeight: s.boxHeight,
      boxLeft: s.boxLeft,
      boxTop: s.boxTop,
      frameWidth: s.frameWidth,
      frameHeight: s.frameHeight,
      yaw: s.yaw,
      pitch: s.pitch,
      roll: s.roll,
      leftEyeOpen: s.leftEyeOpen,
      rightEyeOpen: s.rightEyeOpen,
      hasLeftEye: s.hasLeftEye,
      hasRightEye: s.hasRightEye,
    ));
    final audit = _auditor.audit(
      hasLeftEye: s.hasLeftEye,
      hasRightEye: s.hasRightEye,
      hasNose: s.hasNose,
      hasMouthLeft: s.hasMouthLeft,
      hasMouthRight: s.hasMouthRight,
    );

    StabilityReading? stab;
    if (single) {
      stab = _stability.record(StabilitySample.fromBox(
        left: s.boxLeft,
        top: s.boxTop,
        width: s.boxWidth,
        height: s.boxHeight,
        yaw: s.yaw,
        pitch: s.pitch,
        roll: s.roll,
      ));
      _blink.record(s.leftEyeOpen < s.rightEyeOpen ? s.leftEyeOpen : s.rightEyeOpen);
    } else {
      _stability.reset();
    }

    // Phase 1 forensics for this frame.
    DetectionForensics.logFrame(
      faces: s.faceCount,
      boxLeft: s.boxLeft,
      boxTop: s.boxTop,
      boxWidth: s.boxWidth,
      boxHeight: s.boxHeight,
      rotation: _rotationDegrees(),
      frameWidth: s.frameWidth,
      frameHeight: s.frameHeight,
      yaw: s.yaw,
      pitch: s.pitch,
      roll: s.roll,
      leftEyeOpen: s.leftEyeOpen,
      rightEyeOpen: s.rightEyeOpen,
      blinkDetected: _blink.blinkDetected,
      quality: quality,
      brightness: s.brightness,
      sharpness: s.sharpness,
      stability: stab,
      audit: audit,
    );

    if (!mounted) return;
    setState(() {
      _faceCount = s.faceCount;
      _quality = quality;
      _audit = audit;
      _stab = stab;
      _brightness = s.brightness;
      _sharpness = s.sharpness;
      _yaw = s.yaw;
      _pitch = s.pitch;
      _roll = s.roll;
      _blinkDetected = _blink.blinkDetected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('face_detection_validation_screen'),
      backgroundColor: _deepBlue,
      appBar: AppBar(
        backgroundColor: _deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: _white),
        title: const Text('Face Detection Validation',
            style: TextStyle(color: _white, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SafeArea(child: _error != null ? _errorView() : _dashboard()),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              key: const Key('detection_validation_error'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _red, fontSize: 15)),
        ),
      );

  Widget _dashboard() {
    final q = _quality;
    final bool accepted = _faceCount == 1 && (q?.accepted ?? false);
    final String reason = _faceCount > 1
        ? 'Multiple faces in frame'
        : (q == null ? 'Waiting for frames…' : (q.accepted ? 'OK' : q.rejection.message));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── GREEN / RED status banner ─────────────────────────────────────
          Container(
            key: const Key('detection_status_banner'),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              color: accepted ? _green : _red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(accepted ? Icons.check_circle : Icons.cancel,
                    color: _white, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(accepted ? 'ACCEPTED' : 'REJECTED',
                          key: const Key('detection_verdict'),
                          style: const TextStyle(
                              color: _white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      Text(reason,
                          key: const Key('detection_reason'),
                          style: TextStyle(
                              color: _white.withValues(alpha: 0.9),
                              fontSize: 13)),
                    ],
                  ),
                ),
                Text('${q?.score.round() ?? 0}',
                    key: const Key('detection_score'),
                    style: const TextStyle(
                        color: _white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _metric('FPS', _fps.toStringAsFixed(1)),
          _metric('Face Count', '$_faceCount'),
          _metric('Yaw', '${_yaw.toStringAsFixed(1)}°'),
          _metric('Pitch', '${_pitch.toStringAsFixed(1)}°'),
          _metric('Roll', '${_roll.toStringAsFixed(1)}°'),
          _metric('Brightness', _brightness.toStringAsFixed(0)),
          _metric('Sharpness', _sharpness.toStringAsFixed(1)),
          _metric('Face Coverage',
              '${((q?.faceCoverage ?? 0) * 100).toStringAsFixed(1)}%'),
          _metric('Quality Score', '${q?.score.round() ?? 0} / 100'),
          _metric('Stable Frames',
              '${_stab?.stableFrames ?? 0} / ${widget.requiredStableFrames}'),
          _metric('Blink', _blinkDetected ? 'DETECTED' : 'waiting'),
          _metric('Alignment', _audit?.path.name ?? '—'),
          if (_audit?.isFallback ?? false)
            _metric('Fallback', _audit!.fallbackReason, warn: true),
        ],
      ),
    );
  }

  Widget _metric(String k, String v, {bool warn = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: _white, fontSize: 14)),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: warn ? _saffron : _white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}
