import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../../core/auth_engine/auth_engine_interface.dart';
import '../../core/camera_frame.dart';
import '../../core/face_detection/face_detector_interface.dart';
import '../../core/face_detection/face_quality.dart';
import '../../core/face_detection/face_stability_tracker.dart';
import '../../core/face_preprocessor.dart';
import '../../core/recognition/stable_embedding_collector.dart';
import '../../core/validation/biometric_validation.dart';
import '../../models/auth_result.dart';
import '../widgets/debug_face_overlay.dart';
import '../widgets/face_alignment_overlay.dart';

// ── Frame source abstraction ──────────────────────────────────────────────────

/// Callback type used by [AuthenticationScreen] to obtain camera frames.
///
/// The default implementation reads frames from a real [CameraController].
/// Tests inject a fake implementation that returns synthetic [CameraFrame]
/// objects without requiring a physical camera.
typedef FrameProvider = Stream<CameraFrame> Function();

// ── Screen ────────────────────────────────────────────────────────────────────

/// NHAI Authentication Screen
///
/// Activated when the operator taps "Authenticate Employee" on the Home screen.
/// Navigated to via `Navigator.pushNamed('/authenticate')`.
///
/// Responsibilities:
///   1. Activate the front-facing camera and display a real-time viewfinder
///      with a [FaceAlignmentOverlay] guide (Requirement 6.1).
///   2. On face detection (frame with sharpness > 0), call
///      [AuthEngineInterface.authenticate] (Requirement 6.1).
///   3. While authentication is in progress (after face detected, before
///      result), display "Please blink naturally" prompt (Requirement 7.5).
///   4. On [AuthResult], navigate to `/verification-result` passing the
///      [AuthResult] as a route argument (Requirements 6.1, 7.5).
///
/// Color palette: Deep Blue (#003580) background, White (#FFFFFF) text,
/// Saffron (#FF6600) accent.
///
/// Requirements: 6.1, 7.5
class AuthenticationScreen extends StatefulWidget {
  /// The authentication engine used to verify the captured face.
  final AuthEngineInterface authEngine;

  /// Optional injectable frame source.
  ///
  /// When `null` the screen uses the real [CameraController] (production).
  /// Tests inject a [FrameProvider] that emits synthetic frames so the screen
  /// can be exercised without a physical camera.
  final FrameProvider? frameProvider;

  /// Optional real face detector (ML Kit). When provided, frames are run through
  /// real face detection (bounding box + landmarks) before authentication.
  /// Null in tests (which inject synthetic frames via [frameProvider]).
  final FaceDetectorInterface? faceDetector;

  const AuthenticationScreen({
    super.key,
    required this.authEngine,
    this.frameProvider,
    this.faceDetector,
  });

  @override
  State<AuthenticationScreen> createState() => _AuthenticationScreenState();
}

// ── State ─────────────────────────────────────────────────────────────────────

class _AuthenticationScreenState extends State<AuthenticationScreen> {
  // ── Brand colors ──────────────────────────────────────────────────────────
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _errorRed = Color(0xFFD32F2F);

  // ── Camera (real device only) ─────────────────────────────────────────────
  CameraController? _cameraController;
  CameraDescription? _cameraDescription;
  bool _cameraInitialized = false;
  String? _cameraError;

  /// Maps device orientation to degrees for ML Kit rotation compensation.
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  // ── Frame subscription ────────────────────────────────────────────────────
  StreamSubscription<CameraFrame>? _frameSub;

  // ── Detection / authentication state ─────────────────────────────────────
  FaceAlignmentState _alignmentState = FaceAlignmentState.idle;
  _ScreenPhase _phase = _ScreenPhase.scanning;
  String? _errorMessage;

  // ── Biometric validation gate (Phases 2–6) ───────────────────────────────
  final BiometricGate _gate = BiometricGate(requireBlink: true);
  String _statusMessage = kMsgNoFace;

  // ── Detection-quality + geometric-stability pre-filter ────────────────────
  // Additive hardening: a frame is only collected for recognition when it is
  // high-quality (lighting / sharpness / size / centering / eyes) AND
  // geometrically stable frame-to-frame, on top of the existing blink gate.
  // This does NOT alter the threshold, matcher, engine, or liveness logic.
  static const FaceQualityAnalyzer _qualityAnalyzer = FaceQualityAnalyzer();
  final FaceStabilityTracker _stabilityTracker =
      FaceStabilityTracker(requiredConsecutive: 3);

  /// Collects ≥5 valid frames AFTER blink success; their embeddings are
  /// averaged before recognition (Phase 7). Armed only once the gate passes.
  final StableEmbeddingCollector<CameraFrame> _collector =
      StableEmbeddingCollector<CameraFrame>(target: 5);

  // ── DEBUG MODE (temporary) overlay state ─────────────────────────────────
  String _debugInfo = 'DEBUG: waiting for frames…';
  List<Rect> _debugBoxes = const [];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start camera / frame source once dependencies are available.
    if (_phase == _ScreenPhase.scanning &&
        !_cameraInitialized &&
        _cameraError == null &&
        _frameSub == null) {
      _startCapture();
    }
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  // ── Capture initialisation ────────────────────────────────────────────────

  Future<void> _startCapture() async {
    if (widget.frameProvider != null) {
      // ── Injected frame source (tests / simulation) ──────────────────────
      setState(() => _cameraInitialized = true);
      _frameSub = widget.frameProvider!().listen(_onFrame);
    } else {
      // ── Real camera ─────────────────────────────────────────────────────
      await _initRealCamera();
    }
  }

  Future<void> _initRealCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        // NV21 single-plane is the format ML Kit consumes directly on Android.
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await controller.initialize();

      if (!mounted) return;

      setState(() {
        _cameraController = controller;
        _cameraDescription = frontCamera;
        _cameraInitialized = true;
      });

      // Stream frames from the real camera.
      controller.startImageStream(_handleCameraImage);
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraError = 'Camera initialisation failed: ${e.toString()}';
          _phase = _ScreenPhase.error;
          _errorMessage = _cameraError;
        });
      }
    }
  }

  // Guard so only one detection runs at a time across the frame stream.
  bool _detecting = false;

  /// Handles each camera frame: runs real face detection (when a detector is
  /// injected), enforces single-face capture, and forwards an enriched frame
  /// (RGB + bounding box + eye landmarks) to [_onFrame].
  Future<void> _handleCameraImage(CameraImage image) async {
    if (_phase != _ScreenPhase.scanning || _detecting) return;
    _detecting = true;
    try {
      final base = _cameraImageToFrame(image);
      final detector = widget.faceDetector;
      if (detector == null) {
        _onFrame(base); // legacy/test path (no real detection)
        return;
      }

      final enriched = _enrichFrame(image, base);
      final faces = await detector.detect(enriched);
      if (!mounted || _phase != _ScreenPhase.scanning) return;

      _updateDebug(enriched, faces);

      // Multi-face guard (Phase 11 / fail-closed).
      if (faces.length > 1) {
        _gate.reset();
        _stabilityTracker.reset();
        setState(() {
          _statusMessage = 'Ensure only one person is in frame';
          _alignmentState = FaceAlignmentState.idle;
        });
        return;
      }

      // Build the per-frame observation and drive the biometric gate.
      final observation = faces.isEmpty
          ? const FaceObservation(
              faceDetected: false,
              leftEyeOpen: 0, rightEyeOpen: 0, yaw: 0, roll: 0,
              hasLeftEye: false, hasRightEye: false, hasNoseBase: false,
              hasLeftCheek: false, hasRightCheek: false)
          : _toObservation(faces.first);

      final gateResult = _gate.process(observation);
      _logValidation(observation, gateResult);

      // Detection-quality + stability pre-filter (additive). Only meaningful
      // when a face is present; never blocks the blink challenge because the
      // quality gate has no eye-open hard-gate (closed-eye frames still pass).
      FaceQualityScore? quality;
      bool stableNow = false;
      if (faces.isNotEmpty) {
        final f = faces.first;
        final double brightness =
            FaceQualityAnalyzer.brightnessFromLuma(enriched.bytes);
        // ML Kit returns the bounding box in the ROTATION-APPLIED (upright)
        // coordinate space. For 90°/270° the upright frame's width/height are
        // swapped relative to the raw sensor frame, so centring/size must be
        // normalized against the swapped dimensions or a centred face is wrongly
        // rejected as faceOffCenter (which silently blocked capture).
        final bool swap = enriched.rotationDegrees % 180 == 90;
        final int qFrameW = swap ? enriched.height : enriched.width;
        final int qFrameH = swap ? enriched.width : enriched.height;
        quality = _qualityAnalyzer.analyze(QualityInput(
          faceDetected: true,
          brightness: brightness,
          sharpness: enriched.sharpnessScore,
          boxWidth: f.box.width,
          boxHeight: f.box.height,
          boxLeft: f.box.left,
          boxTop: f.box.top,
          frameWidth: qFrameW,
          frameHeight: qFrameH,
          yaw: f.headEulerAngleY ?? 0,
          pitch: f.headEulerAngleX ?? 0,
          roll: f.headEulerAngleZ ?? 0,
          leftEyeOpen: f.leftEyeOpenProbability ?? 1.0,
          rightEyeOpen: f.rightEyeOpenProbability ?? 1.0,
          hasLeftEye: f.hasLeftEye,
          hasRightEye: f.hasRightEye,
        ));
        stableNow = _stabilityTracker
            .record(StabilitySample.fromBox(
              left: f.box.left,
              top: f.box.top,
              width: f.box.width,
              height: f.box.height,
              yaw: f.headEulerAngleY ?? 0,
              pitch: f.headEulerAngleX ?? 0,
              roll: f.headEulerAngleZ ?? 0,
            ))
            .stable;
        // TEMP forensics: prove each handoff between detection and recognition.
        debugPrint('[PIPELINE] Detection Passed faces=1 '
            'quality=${quality.accepted} reason=${quality.rejection.name} '
            'coverage=${quality.faceCoverage.toStringAsFixed(3)} '
            'centerOffset=${quality.centerOffset.toStringAsFixed(3)}');
        if (stableNow) debugPrint('[PIPELINE] Stability Passed');
      } else {
        _stabilityTracker.reset();
      }

      setState(() {
        // Prefer the specific quality reason (e.g. "Move closer") when a face is
        // present but low-quality; otherwise show the gate's message.
        _statusMessage =
            (quality != null && !quality.accepted) ? quality.reasonMessage : gateResult.message;
        _alignmentState =
            gateResult.validation.valid && (quality?.accepted ?? false)
                ? FaceAlignmentState.detected
                : FaceAlignmentState.idle;
      });

      // Recognition only begins AFTER the blink gate passes. The blink itself
      // contains an eyes-closed (invalid) frame, so we must NOT collect during
      // the gate — we arm the collector once the gate passes and then gather a
      // minimum of [target] valid frames whose embeddings are averaged.
      if (!gateResult.passed) return;
      debugPrint('[PIPELINE] Blink Passed');

      if (!_collector.isArmed) _collector.arm();

      // Only collect frames that are valid (gate), high-quality, AND stable.
      if (gateResult.validation.valid &&
          faces.isNotEmpty &&
          (quality?.accepted ?? false) &&
          stableNow) {
        final f = faces.first;
        final frame = enriched.copyWith(
          faceCount: 1,
          faceBox: FaceBoxData(
            left: f.box.left,
            top: f.box.top,
            width: f.box.width,
            height: f.box.height,
          ),
          landmarks: f.eyeLandmarks,
          leftEye: f.leftEyePosition,
          rightEye: f.rightEyePosition,
          noseBase: f.noseBasePosition,
          mouthLeft: f.mouthLeftPosition,
          mouthRight: f.mouthRightPosition,
        );
        if (_collector.offer(frame, valid: true)) {
          debugPrint(
              '[Recognition] Collected embedding ${_collector.count}/${_collector.target}');
        }
      }

      if (_collector.isComplete) {
        debugPrint('[Recognition] Average complete');
        debugPrint(
            '[PIPELINE] Capture Triggered frames=${_collector.count}');
        _proceedToAuthentication(_collector.items.toList());
      }
    } catch (e, st) {
      // Surface detection/conversion errors instead of silently stalling at 0/3.
      debugPrint('[AuthScreen] _handleCameraImage error: $e\n$st');
    } finally {
      _detecting = false;
    }
  }

  /// Builds a [FaceObservation] from an ML Kit [DetectedFace]. Eye-open
  /// probabilities default to 1.0 (open) only if classification is unavailable.
  FaceObservation _toObservation(DetectedFace f) => FaceObservation(
        faceDetected: true,
        leftEyeOpen: f.leftEyeOpenProbability ?? 1.0,
        rightEyeOpen: f.rightEyeOpenProbability ?? 1.0,
        yaw: f.headEulerAngleY ?? 0.0,
        roll: f.headEulerAngleZ ?? 0.0,
        hasLeftEye: f.hasLeftEye,
        hasRightEye: f.hasRightEye,
        hasNoseBase: f.hasNoseBase,
        hasLeftCheek: f.hasLeftCheek,
        hasRightCheek: f.hasRightCheek,
      );

  /// Phase 9 — structured validation/liveness logs.
  void _logValidation(FaceObservation o, GateResult r) {
    debugPrint('[Validation] eyesOpen='
        '${o.leftEyeOpen >= FaceValidator.eyeOpenMinProbability && o.rightEyeOpen >= FaceValidator.eyeOpenMinProbability}');
    debugPrint('[Validation] occlusion=${!o.allCriticalLandmarksPresent}');
    debugPrint('[Validation] headPosePass='
        '${o.yaw.abs() <= FaceValidator.maxYawDegrees && o.roll.abs() <= FaceValidator.maxRollDegrees}');
    debugPrint('[Validation] validFrames=${r.validFrames} stage=${r.stage}');
    debugPrint('[Liveness] blinkDetected=${r.blinkDetected}');
  }

  /// Updates the temporary on-screen DEBUG overlay with the latest detection.
  void _updateDebug(CameraFrame frame, List<DetectedFace> faces) {
    final boxes = faces
        .map((f) => Rect.fromLTWH(
              f.box.left / frame.width,
              f.box.top / frame.height,
              f.box.width / frame.width,
              f.box.height / frame.height,
            ))
        .toList();
    final first = faces.isEmpty ? 'none' : faces.first.box.toString();
    setState(() {
      _debugBoxes = boxes;
      _debugInfo = 'DEBUG faces=${faces.length} rot=${frame.rotationDegrees}° '
          'img=${frame.width}x${frame.height} box=$first';
    });
  }

  /// Computes the ML Kit input rotation (degrees) from the camera sensor
  /// orientation and the current device orientation. Hardcoding 0 here is the
  /// classic cause of "face visible but 0 detections" in portrait.
  int _computeRotationDegrees() {
    final cam = _cameraDescription;
    final ctrl = _cameraController;
    if (cam == null || ctrl == null) return 0;
    final int sensor = cam.sensorOrientation;
    int compensation = _orientations[ctrl.value.deviceOrientation] ?? 0;
    if (cam.lensDirection == CameraLensDirection.front) {
      compensation = (sensor + compensation) % 360;
    } else {
      compensation = (sensor - compensation + 360) % 360;
    }
    return compensation;
  }

  /// Builds the ML Kit input (NV21 bytes + stride + rotation) and a full-frame
  /// RGB buffer for cropping. Prefers the camera's native single-plane NV21
  /// (the format ML Kit consumes directly); falls back to manual YUV420→NV21.
  CameraFrame _enrichFrame(CameraImage image, CameraFrame base) {
    final int rotation = _computeRotationDegrees();
    // VERBOSE: format + plane diagnostics for every frame.
    debugPrint(
      '[AuthScreen] _enrichFrame format=${image.format.group} '
      'raw=${image.format.raw} w=${image.width} h=${image.height} '
      'planes=${image.planes.length} '
      'bytesPerRow=[${image.planes.map((p) => p.bytesPerRow).join(",")}] '
      'sensorOri=${_cameraDescription?.sensorOrientation} '
      'deviceOri=${_cameraController?.value.deviceOrientation} '
      'rotationDeg=$rotation',
    );

    if (image.planes.length == 1) {
      // Native NV21 (Android): pass the plane bytes straight through.
      final p = image.planes.first;
      final rgb = FacePreprocessor.nv21ToRgb(
        p.bytes, image.width, image.height,
        bytesPerRow: p.bytesPerRow,
      );
      return base.copyWith(
        rgbBytes: rgb,
        nv21Bytes: p.bytes,
        nv21BytesPerRow: p.bytesPerRow,
        rotationDegrees: rotation,
      );
    }

    // Fallback: multi-plane YUV420 → manual NV21 + RGB.
    final y = image.planes[0];
    final u = image.planes[1];
    final v = image.planes[2];
    final int uvPixelStride = u.bytesPerPixel ?? 2;
    final rgb = FacePreprocessor.yuv420ToRgb(
      y.bytes, u.bytes, v.bytes, image.width, image.height,
      yRowStride: y.bytesPerRow, uvRowStride: u.bytesPerRow,
      uvPixelStride: uvPixelStride,
    );
    final nv21 = FacePreprocessor.yuv420ToNv21(
      y.bytes, u.bytes, v.bytes, image.width, image.height,
      yRowStride: y.bytesPerRow, uvRowStride: u.bytesPerRow,
      uvPixelStride: uvPixelStride,
    );
    return base.copyWith(
      rgbBytes: rgb,
      nv21Bytes: nv21,
      nv21BytesPerRow: image.width,
      rotationDegrees: rotation,
    );
  }

  /// Converts a [CameraImage] from the camera plugin into a [CameraFrame].
  CameraFrame _cameraImageToFrame(CameraImage image) {
    final yPlane = image.planes.first;
    // DEBUG: compute a real Laplacian-variance sharpness score from the Y-plane.
    final double computedSharpness = _computeSharpness(
      yPlane.bytes,
      image.width,
      image.height,
    );
    // ignore: avoid_print
    debugPrint(
      '[AuthScreen] frame ${image.width}x${image.height} '
      'sharpnessScore=$computedSharpness '
      '(threshold=10.0, bytes=${yPlane.bytes.length})',
    );
    return CameraFrame(
      bytes: yPlane.bytes,
      width: image.width,
      height: image.height,
      sharpnessScore: computedSharpness,
    );
  }

  /// Computes a Laplacian-variance sharpness score from a Y-plane byte buffer.
  ///
  /// See [_FaceCaptureScreenState._computeSharpness] for algorithm details.
  static double _computeSharpness(List<int> yBytes, int width, int height) {
    if (yBytes.isEmpty || width < 3 || height < 3) return 0.0;

    const int sampleGrid = 64;
    final int stepX = (width / sampleGrid).ceil().clamp(1, width);
    final int stepY = (height / sampleGrid).ceil().clamp(1, height);

    final List<double> responses = [];

    for (int y = 1; y < height - 1; y += stepY) {
      for (int x = 1; x < width - 1; x += stepX) {
        final int center = y * width + x;
        final double lap = (yBytes[center - width] +
                yBytes[center + width] +
                yBytes[center - 1] +
                yBytes[center + 1] -
                4 * yBytes[center])
            .toDouble();
        responses.add(lap);
      }
    }

    if (responses.isEmpty) return 0.0;

    final double mean = responses.reduce((a, b) => a + b) / responses.length;
    final double variance = responses
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        responses.length;
    return variance;
  }

  // ── Frame processing ──────────────────────────────────────────────────────

  void _onFrame(CameraFrame frame) {
    if (_phase != _ScreenPhase.scanning) return;

    // A frame with sharpness > 0 and non-empty bytes is treated as
    // "face detected". This mirrors the heuristic used in FaceCaptureScreen.
    final bool faceDetected =
        frame.sharpnessScore > 0 && frame.bytes.isNotEmpty;

    if (faceDetected) {
      if (_alignmentState != FaceAlignmentState.detected) {
        setState(() => _alignmentState = FaceAlignmentState.detected);
      }
      _proceedToAuthentication([frame]);
    }
  }

  // ── Authentication ────────────────────────────────────────────────────────

  Future<void> _proceedToAuthentication(List<CameraFrame> frames) async {
    // Guard: only run once.
    if (_phase != _ScreenPhase.scanning) return;
    if (frames.isEmpty) return;

    setState(() => _phase = _ScreenPhase.authenticating);

    // Stop the frame stream while authentication is in progress.
    await _frameSub?.cancel();
    _frameSub = null;
    await _cameraController?.stopImageStream();

    try {
      // Averages embeddings across the stable frames (single frame for the
      // legacy/test path). The engine emits [Embedding] and [MatcherAudit] /
      // [Decision] between these two markers.
      debugPrint('[PIPELINE] Recognition Started frames=${frames.length}');
      final result = await widget.authEngine.authenticateAveraged(frames);
      debugPrint('[PIPELINE] Authentication Result '
          'classification=${result.classification.name} '
          'trust=${result.trustScore.toStringAsFixed(3)} '
          'matched=${result.matchedEmployeeId ?? "none"}');

      if (!mounted) return;

      // Navigate to the result screen, passing the AuthResult as argument.
      Navigator.of(context).pushReplacementNamed(
        '/verification-result',
        arguments: result,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _ScreenPhase.error;
        _errorMessage =
            'Authentication failed unexpectedly. Please try again.\n'
            '${e.toString()}';
      });
    }
  }

  // ── Retry ─────────────────────────────────────────────────────────────────

  void _retry() {
    _frameSub?.cancel();
    _frameSub = null;

    _gate.reset();
    _collector.reset();
    _stabilityTracker.reset();
    setState(() {
      _phase = _ScreenPhase.scanning;
      _alignmentState = FaceAlignmentState.idle;
      _errorMessage = null;
      _cameraInitialized = false;
      _cameraError = null;
    });

    _startCapture();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('authentication_screen'),
      backgroundColor: _deepBlue,
      appBar: AppBar(
        key: const Key('authentication_app_bar'),
        backgroundColor: _deepBlue,
        elevation: 0,
        leading: IconButton(
          key: const Key('back_button'),
          icon: const Icon(Icons.arrow_back_ios_new, color: _white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
        title: const Text(
          'Authenticate Employee',
          key: Key('app_bar_title'),
          style: TextStyle(
            color: _white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            key: const Key('saffron_accent_bar'),
            color: _saffron,
            height: 2,
          ),
        ),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _ScreenPhase.scanning:
        return _buildScanView();
      case _ScreenPhase.authenticating:
        return _buildAuthenticatingView();
      case _ScreenPhase.error:
        return _buildErrorView();
    }
  }

  // ── Scan view ─────────────────────────────────────────────────────────────

  Widget _buildScanView() {
    if (!_cameraInitialized) {
      return const Center(
        child: CircularProgressIndicator(
          key: Key('camera_loading_indicator'),
          valueColor: AlwaysStoppedAnimation<Color>(_saffron),
        ),
      );
    }

    return Stack(
      key: const Key('scan_view'),
      fit: StackFit.expand,
      children: [
        // ── Camera preview (real device) or placeholder (tests) ─────────────
        if (_cameraController != null && _cameraController!.value.isInitialized)
          CameraPreview(
            key: const Key('camera_preview'),
            _cameraController!,
          )
        else
          Container(
            key: const Key('camera_placeholder'),
            color: Colors.black,
          ),

        // ── Face alignment overlay ───────────────────────────────────────────
        FaceAlignmentOverlay(
          key: const Key('face_alignment_overlay'),
          state: _alignmentState,
        ),

        // ── TEMPORARY DEBUG overlay (only when a real detector is active) ─────
        if (widget.faceDetector != null)
          DebugFaceOverlay(
            normalizedBoxes: _debugBoxes,
            info: _debugInfo,
          ),

        // ── Bottom instruction bar ───────────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _InstructionBar(
            key: const Key('instruction_bar'),
            faceDetected: _alignmentState == FaceAlignmentState.detected,
            message: widget.faceDetector != null ? _statusMessage : null,
          ),
        ),
      ],
    );
  }

  // ── Authenticating view (liveness prompt) ─────────────────────────────────

  Widget _buildAuthenticatingView() {
    return Center(
      key: const Key('authenticating_view'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            key: Key('processing_indicator'),
            valueColor: AlwaysStoppedAnimation<Color>(_saffron),
          ),
          const SizedBox(height: 32),
          // Liveness prompt — displayed while VERIFIED face check is pending
          // liveness confirmation (Requirement 7.5).
          Container(
            key: const Key('liveness_prompt_container'),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: _white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _saffron.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.remove_red_eye_outlined,
                  key: const Key('liveness_icon'),
                  color: _saffron,
                  size: 22,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Please blink naturally',
                  key: Key('blink_prompt'),
                  style: TextStyle(
                    color: _white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Verifying identity…',
            key: const Key('verifying_label'),
            style: TextStyle(
              color: _white.withValues(alpha: 0.65),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // ── Error view ────────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    return SingleChildScrollView(
      key: const Key('error_view'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Error icon ───────────────────────────────────────────────────
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _errorRed.withValues(alpha: 0.12),
                border: Border.fromBorderSide(
                  BorderSide(color: _errorRed, width: 3),
                ),
              ),
              child: Icon(
                Icons.error_outline,
                key: const Key('error_icon'),
                color: _errorRed,
                size: 56,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Headline ─────────────────────────────────────────────────────
          const Text(
            'Authentication Error',
            key: Key('error_headline'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFEF9A9A),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),

          const SizedBox(height: 16),

          // ── Human-readable error message ──────────────────────────────────
          Container(
            key: const Key('error_message_container'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _errorRed.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _errorRed.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Text(
              _errorMessage ?? 'An unexpected error occurred. Please retry.',
              key: const Key('auth_error_message'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFEF9A9A),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),

          const SizedBox(height: 40),

          // ── Retry button ──────────────────────────────────────────────────
          ElevatedButton.icon(
            key: const Key('retry_button'),
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: const Text(
              'Try Again',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _saffron,
              foregroundColor: _white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
            ),
          ),

          const SizedBox(height: 16),

          // ── Return to Home button ─────────────────────────────────────────
          OutlinedButton(
            key: const Key('return_home_button'),
            onPressed: () => Navigator.of(context)
                .pushNamedAndRemoveUntil('/home', (_) => false),
            style: OutlinedButton.styleFrom(
              foregroundColor: _white,
              side: BorderSide(
                  color: _white.withValues(alpha: 0.4), width: 1.2),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Return to Home',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Screen phase enum ─────────────────────────────────────────────────────────

enum _ScreenPhase {
  /// Camera is active and scanning for a face.
  scanning,

  /// Face detected; authentication (including liveness) is in progress.
  authenticating,

  /// An error occurred (camera init, auth engine exception, etc.).
  error,
}

// ── Helper widgets ────────────────────────────────────────────────────────────

/// Bottom instruction bar shown during the scanning phase.
class _InstructionBar extends StatelessWidget {
  final bool faceDetected;

  /// When provided (device path with a real detector), this user-friendly
  /// validation message replaces the default instruction text (Phase 10).
  final String? message;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _green = Color(0xFF4CAF50);

  const _InstructionBar({
    super.key,
    required this.faceDetected,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('instruction_bar_container'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: _deepBlue.withValues(alpha: 0.85),
        border: Border(
          top: BorderSide(
            color: faceDetected ? _green : _saffron,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            faceDetected ? Icons.face : Icons.face_retouching_natural,
            color: faceDetected ? _green : _saffron,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message ??
                  (faceDetected
                      ? 'Face detected — verifying identity'
                      : 'Look directly at the camera and position your face within the guide'),
              style: const TextStyle(
                color: _white,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
