import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../../core/camera_frame.dart';
import '../../core/enrollment_module/enrollment_module_interface.dart';
import '../../core/face_detection/face_detector_interface.dart';
import '../../core/face_preprocessor.dart';
import '../../core/validation/biometric_validation.dart';
import '../widgets/debug_face_overlay.dart';
import '../widgets/face_alignment_overlay.dart';

// ── Frame source abstraction ──────────────────────────────────────────────────

/// Callback type used by [FaceCaptureScreen] to obtain camera frames.
///
/// The default implementation reads frames from a real [CameraController].
/// Tests inject a fake implementation that returns synthetic [CameraFrame]
/// objects without requiring a physical camera.
typedef FrameProvider = Stream<CameraFrame> Function();

// ── Screen ────────────────────────────────────────────────────────────────────

/// NHAI Face Capture Screen — Enrollment Mode
///
/// Activated after the operator completes the [EnrollmentFormScreen].
/// Receives [EmployeeFormData] as a route argument via
/// `Navigator.pushNamed('/face-capture', arguments: formData)`.
///
/// Responsibilities:
///   1. Activate the front-facing camera and display a real-time viewfinder
///      with a [FaceAlignmentOverlay] guide (Requirement 4.1).
///   2. Show a green border when a face is detected within the guide
///      (Requirement 4.2).
///   3. Show a "No face detected" message after 10 seconds without detection
///      (Requirement 4.3).
///   4. Capture ≥ 3 frames, select the best via
///      [EnrollmentModuleInterface.selectBestFrame], then call
///      [EnrollmentModuleInterface.enroll] (Requirements 4.4, 4.5).
///   5. On success, navigate to the enrollment confirmation view
///      (Requirement 5.3).
///   6. On error, display a human-readable message with a retry option
///      (Requirement 4.7).
///
/// Color palette: Deep Blue (#003580) background, White (#FFFFFF) text,
/// Saffron (#FF6600) accent.
///
/// Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.7, 5.3
class FaceCaptureScreen extends StatefulWidget {
  /// The enrollment module used for frame selection and enrollment.
  final EnrollmentModuleInterface enrollmentModule;

  /// Employee data collected from [EnrollmentFormScreen].
  ///
  /// When the screen is pushed via named route the argument is extracted from
  /// [ModalRoute.settings.arguments] in [initState]. When provided directly
  /// (e.g., in widget tests) this value is used as-is.
  final EmployeeFormData? formData;

  /// Optional injectable frame source.
  ///
  /// When `null` the screen uses the real [CameraController] (production).
  /// Tests inject a [FrameProvider] that emits synthetic frames so the screen
  /// can be exercised without a physical camera.
  final FrameProvider? frameProvider;

  /// Minimum number of frames to collect before attempting enrollment.
  ///
  /// Exposed for testing; defaults to 3 (Requirement 4.4).
  final int minFrameCount;

  /// Duration after which the "no face detected" message is shown.
  ///
  /// Exposed for testing; defaults to 10 seconds (Requirement 4.3).
  final Duration noFaceTimeout;

  /// Optional real face detector (ML Kit). Null in tests.
  final FaceDetectorInterface? faceDetector;

  const FaceCaptureScreen({
    super.key,
    required this.enrollmentModule,
    this.formData,
    this.frameProvider,
    this.minFrameCount = 3,
    this.noFaceTimeout = const Duration(seconds: 10),
    this.faceDetector,
  });

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

// ── State ─────────────────────────────────────────────────────────────────────

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  // ── Brand colors ──────────────────────────────────────────────────────────
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _errorRed = Color(0xFFD32F2F);

  // ── Route argument ────────────────────────────────────────────────────────
  EmployeeFormData? _formData;

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

  // ── Frame collection ──────────────────────────────────────────────────────
  final List<CameraFrame> _capturedFrames = [];
  StreamSubscription<CameraFrame>? _frameSub;

  // ── Detection state ───────────────────────────────────────────────────────
  FaceAlignmentState _alignmentState = FaceAlignmentState.idle;
  Timer? _noFaceTimer;
  bool _noFaceMessageVisible = false;

  // ── Per-frame face-quality validator (Phases 2–4) for enrollment ─────────
  static const FaceValidator _validator = FaceValidator();

  // ── DEBUG MODE (temporary) overlay state ─────────────────────────────────
  String _debugInfo = 'DEBUG: waiting for frames…';
  List<Rect> _debugBoxes = const [];

  // ── Enrollment state ──────────────────────────────────────────────────────
  _ScreenPhase _phase = _ScreenPhase.capturing;
  String? _errorMessage;
  EnrollmentResult? _enrollmentResult;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _formData = widget.formData;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Extract route argument if not provided directly.
    if (_formData == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is EmployeeFormData) {
        _formData = args;
      }
    }
    // Start camera / frame source once dependencies are available.
    if (_phase == _ScreenPhase.capturing &&
        !_cameraInitialized &&
        _cameraError == null &&
        _frameSub == null) {
      _startCapture();
    }
  }

  @override
  void dispose() {
    _noFaceTimer?.cancel();
    _frameSub?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  // ── Capture initialisation ────────────────────────────────────────────────

  Future<void> _startCapture() async {
    if (widget.frameProvider != null) {
      // ── Injected frame source (tests / simulation) ──────────────────────
      setState(() => _cameraInitialized = true);
      _startNoFaceTimer();
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

      _startNoFaceTimer();

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

  /// Converts a [CameraImage] from the camera plugin into a [CameraFrame].
  ///
  /// Computes a real Laplacian-variance sharpness score from the Y-plane luma
  /// data via [_computeSharpness] and assigns it to [CameraFrame.sharpnessScore].
  /// This score is used by [AuthEngineImpl.extractEmbedding] to gate quality
  /// (threshold: 10.0). Typical values for a well-lit face are 30–200.
  // Guard so only one detection runs at a time across the frame stream.
  bool _detecting = false;

  /// Runs real face detection (when a detector is injected) and forwards an
  /// enriched frame (RGB + box + landmarks + face count) to [_onFrame]. Frames
  /// with no face are skipped so enrollment never proceeds without a face.
  Future<void> _handleCameraImage(CameraImage image) async {
    if (_phase != _ScreenPhase.capturing || _detecting) return;
    _detecting = true;
    try {
      final base = _cameraImageToFrame(image);
      final detector = widget.faceDetector;
      if (detector == null) {
        _onFrame(base); // legacy/test path
        return;
      }
      final enriched = _enrichFrame(image, base);
      final faces = await detector.detect(enriched);
      if (!mounted || _phase != _ScreenPhase.capturing) return;

      _updateDebug(enriched, faces);
      if (faces.length > 1) return; // only one person may enroll
      if (faces.isEmpty) return; // no face → keep capturing

      // Phase 2–4: only collect frames of a valid (eyes-open, unoccluded,
      // straight) face — never enroll a low-quality / occluded capture.
      final f = faces.first;
      final v = _validator.validate(FaceObservation(
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
      ));
      debugPrint('[Validation] enroll valid=${v.valid} reason=${v.failure}');
      if (!v.valid) return; // skip invalid frames

      final box = f.box;
      _onFrame(enriched.copyWith(
        faceCount: 1,
        faceBox: FaceBoxData(
          left: box.left,
          top: box.top,
          width: box.width,
          height: box.height,
        ),
        landmarks: f.eyeLandmarks,
        leftEye: f.leftEyePosition,
        rightEye: f.rightEyePosition,
      ));
    } catch (e, st) {
      // Surface detection/conversion errors instead of silently stalling at 0/3.
      debugPrint('[FaceCaptureScreen] _handleCameraImage error: $e\n$st');
    } finally {
      _detecting = false;
    }
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
  /// orientation and the current device orientation.
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

  /// Builds the ML Kit input (NV21 + stride + rotation) and an RGB buffer.
  /// Prefers the camera's native single-plane NV21; falls back to manual
  /// YUV420→NV21 conversion.
  CameraFrame _enrichFrame(CameraImage image, CameraFrame base) {
    final int rotation = _computeRotationDegrees();
    debugPrint(
      '[FaceCaptureScreen] _enrichFrame format=${image.format.group} '
      'raw=${image.format.raw} w=${image.width} h=${image.height} '
      'planes=${image.planes.length} '
      'bytesPerRow=[${image.planes.map((p) => p.bytesPerRow).join(",")}] '
      'sensorOri=${_cameraDescription?.sensorOrientation} '
      'deviceOri=${_cameraController?.value.deviceOrientation} '
      'rotationDeg=$rotation',
    );

    if (image.planes.length == 1) {
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
      '[FaceCapture] frame ${image.width}x${image.height} '
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
  /// Samples a 64×64 grid of pixels from the luma plane, applies a 3×3
  /// Laplacian kernel, and returns the variance of the response values.
  /// Higher variance = sharper image.  Typical values for a well-lit face
  /// at arm's length are 30–200; blurry frames score < 10.
  ///
  /// This is a pure-Dart implementation — no native code required.
  static double _computeSharpness(List<int> yBytes, int width, int height) {
    if (yBytes.isEmpty || width < 3 || height < 3) return 0.0;

    // Sample at most 64×64 evenly-spaced interior pixels to keep it fast.
    const int sampleGrid = 64;
    final int stepX = (width / sampleGrid).ceil().clamp(1, width);
    final int stepY = (height / sampleGrid).ceil().clamp(1, height);

    // 3×3 Laplacian kernel: [0,1,0 / 1,-4,1 / 0,1,0]
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

    // Variance of Laplacian responses.
    final double mean = responses.reduce((a, b) => a + b) / responses.length;
    final double variance = responses
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        responses.length;
    return variance;
  }

  // ── No-face timeout ───────────────────────────────────────────────────────

  void _startNoFaceTimer() {
    _noFaceTimer?.cancel();
    _noFaceTimer = Timer(widget.noFaceTimeout, () {
      if (!mounted) return;
      if (_alignmentState != FaceAlignmentState.detected) {
        setState(() {
          _alignmentState = FaceAlignmentState.timeout;
          _noFaceMessageVisible = true;
        });
      }
    });
  }

  // ── Frame processing ──────────────────────────────────────────────────────

  void _onFrame(CameraFrame frame) {
    if (_phase != _ScreenPhase.capturing) return;

    // Heuristic: a frame with sharpness > 0 and non-empty bytes is treated as
    // "face detected". In production the enrollment module / ML pipeline would
    // provide a proper face-detection signal; here we use sharpness as a proxy
    // so the UI state machine works correctly in both real and test scenarios.
    final bool faceDetected =
        frame.sharpnessScore > 0 && frame.bytes.isNotEmpty;

    if (faceDetected) {
      // Cancel the no-face timer and mark face as detected.
      _noFaceTimer?.cancel();
      if (_alignmentState != FaceAlignmentState.detected) {
        setState(() {
          _alignmentState = FaceAlignmentState.detected;
          _noFaceMessageVisible = false;
        });
      }

      // Collect frames up to the minimum required count.
      if (_capturedFrames.length < widget.minFrameCount) {
        _capturedFrames.add(frame);
      }

      // Once we have enough frames, proceed to enrollment.
      if (_capturedFrames.length >= widget.minFrameCount &&
          _phase == _ScreenPhase.capturing) {
        _proceedToEnrollment();
      }
    }
  }

  // ── Enrollment ────────────────────────────────────────────────────────────

  Future<void> _proceedToEnrollment() async {
    // Guard: only run once.
    if (_phase != _ScreenPhase.capturing) return;
    setState(() => _phase = _ScreenPhase.processing);

    // Stop the frame stream while processing.
    await _frameSub?.cancel();
    _frameSub = null;
    await _cameraController?.stopImageStream();

    final formData = _formData;
    if (formData == null) {
      setState(() {
        _phase = _ScreenPhase.error;
        _errorMessage =
            'Employee data is missing. Please go back and re-enter the form.';
      });
      return;
    }

    final result = await widget.enrollmentModule.enroll(
      formData,
      List.unmodifiable(_capturedFrames),
    );

    if (!mounted) return;

    if (result.success && result.record != null) {
      setState(() {
        _phase = _ScreenPhase.success;
        _enrollmentResult = result;
      });
    } else {
      // Determine if this is a quality-below-threshold error (Requirement 4.5).
      final msg = result.errorMessage ?? 'Enrollment failed. Please retry.';
      final bool isQualityError = msg.toLowerCase().contains('quality') ||
          msg.toLowerCase().contains('low') ||
          msg.toLowerCase().contains('sharpness');

      setState(() {
        _phase = _ScreenPhase.error;
        _errorMessage = isQualityError
            ? 'Image quality is too low. Please ensure good lighting and '
                'hold the device steady, then retake.'
            : msg;
      });
    }
  }

  // ── Retry ─────────────────────────────────────────────────────────────────

  void _retry() {
    _noFaceTimer?.cancel();
    _frameSub?.cancel();
    _frameSub = null;
    _capturedFrames.clear();

    setState(() {
      _phase = _ScreenPhase.capturing;
      _alignmentState = FaceAlignmentState.idle;
      _noFaceMessageVisible = false;
      _errorMessage = null;
      _enrollmentResult = null;
      _cameraInitialized = false;
      _cameraError = null;
    });

    _startCapture();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deepBlue,
      appBar: AppBar(
        backgroundColor: _deepBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
        title: const Text(
          'Face Capture',
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
          child: Container(color: _saffron, height: 2),
        ),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _ScreenPhase.capturing:
        return _buildCaptureView();
      case _ScreenPhase.processing:
        return _buildProcessingView();
      case _ScreenPhase.success:
        return _buildSuccessView();
      case _ScreenPhase.error:
        return _buildErrorView();
    }
  }

  // ── Capture view ──────────────────────────────────────────────────────────

  Widget _buildCaptureView() {
    if (!_cameraInitialized) {
      return const Center(
        child: CircularProgressIndicator(
          key: Key('camera_loading_indicator'),
          valueColor: AlwaysStoppedAnimation<Color>(_saffron),
        ),
      );
    }

    // Determine the overlay message.
    String? overlayMessage;
    if (_noFaceMessageVisible) {
      overlayMessage =
          'No face detected — please position face within the guide';
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Camera preview (real device) or placeholder (tests) ─────────────
        if (_cameraController != null && _cameraController!.value.isInitialized)
          CameraPreview(
            key: const Key('camera_preview'),
            _cameraController!,
          )
        else
          // Placeholder shown when using an injected frame provider (tests)
          // or while the camera is initialising.
          Container(
            key: const Key('camera_placeholder'),
            color: Colors.black,
          ),

        // ── Face alignment overlay ───────────────────────────────────────────
        FaceAlignmentOverlay(
          key: const Key('face_alignment_overlay'),
          state: _alignmentState,
          message: overlayMessage,
        ),

        // ── TEMPORARY DEBUG overlay (only when a real detector is active) ─────
        if (widget.faceDetector != null)
          DebugFaceOverlay(
            normalizedBoxes: _debugBoxes,
            info: _debugInfo,
          ),

        // ── Frame counter (debug / accessibility) ────────────────────────────
        Positioned(
          top: 12,
          right: 16,
          child: _FrameCounter(
            key: const Key('frame_counter'),
            captured: _capturedFrames.length,
            required: widget.minFrameCount,
          ),
        ),

        // ── Bottom instruction bar ───────────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _InstructionBar(
            key: const Key('instruction_bar'),
            faceDetected: _alignmentState == FaceAlignmentState.detected,
          ),
        ),
      ],
    );
  }

  // ── Processing view ───────────────────────────────────────────────────────

  Widget _buildProcessingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            key: Key('processing_indicator'),
            valueColor: AlwaysStoppedAnimation<Color>(_saffron),
          ),
          const SizedBox(height: 24),
          const Text(
            'Processing enrollment…',
            key: Key('processing_label'),
            style: TextStyle(
              color: _white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Success view ──────────────────────────────────────────────────────────

  Widget _buildSuccessView() {
    final record = _enrollmentResult?.record;
    final employeeName = record?.name ?? _formData?.name ?? '—';
    final employeeId = record?.employeeId ?? _formData?.employeeId ?? '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Success icon ─────────────────────────────────────────────────
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                border: const Border.fromBorderSide(
                  BorderSide(color: Color(0xFF4CAF50), width: 3),
                ),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                key: Key('success_icon'),
                color: Color(0xFF4CAF50),
                size: 56,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Headline ─────────────────────────────────────────────────────
          const Text(
            'Enrollment Successful',
            key: Key('success_headline'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF4CAF50),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'The employee has been enrolled successfully.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _white.withValues(alpha: 0.75),
              fontSize: 14,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // ── Employee details card ─────────────────────────────────────────
          Container(
            key: const Key('enrollment_confirmation_card'),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _saffron.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(
                  key: const Key('enrolled_name_row'),
                  label: 'Name',
                  value: employeeName,
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  key: const Key('enrolled_id_row'),
                  label: 'Employee ID',
                  value: employeeId,
                ),
                if (record?.department != null) ...[
                  const SizedBox(height: 12),
                  _DetailRow(
                    key: const Key('enrolled_department_row'),
                    label: 'Department',
                    value: record!.department,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 40),

          // ── Return to Home button ─────────────────────────────────────────
          ElevatedButton(
            key: const Key('return_home_button'),
            onPressed: () =>
                Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false),
            style: ElevatedButton.styleFrom(
              backgroundColor: _saffron,
              foregroundColor: _white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
            ),
            child: const Text(
              'Return to Home',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error view ────────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    return SingleChildScrollView(
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
            'Enrollment Failed',
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
              key: const Key('error_message_text'),
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
              'Retry Capture',
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

          // ── Back button ───────────────────────────────────────────────────
          OutlinedButton(
            key: const Key('back_button'),
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: _white,
              side: BorderSide(color: _white.withValues(alpha: 0.4), width: 1.2),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Back to Form',
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
  /// Camera is active and frames are being collected.
  capturing,

  /// Frames collected; enrollment is in progress.
  processing,

  /// Enrollment completed successfully.
  success,

  /// An error occurred (camera init, quality, storage, etc.).
  error,
}

// ── Helper widgets ────────────────────────────────────────────────────────────

/// Small badge showing how many frames have been captured vs. required.
class _FrameCounter extends StatelessWidget {
  final int captured;
  final int required;

  static const Color _white = Color(0xFFFFFFFF);

  const _FrameCounter({
    super.key,
    required this.captured,
    required this.required,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Frames: $captured / $required',
        style: const TextStyle(
          color: _white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Bottom instruction bar shown during the capture phase.
class _InstructionBar extends StatelessWidget {
  final bool faceDetected;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _green = Color(0xFF4CAF50);

  const _InstructionBar({
    super.key,
    required this.faceDetected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              faceDetected
                  ? 'Face detected — hold still while frames are captured'
                  : 'Look directly at the camera and position your face within the guide',
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

/// A label + value row used in the enrollment confirmation card.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);

  const _DetailRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              color: _saffron,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: _white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
