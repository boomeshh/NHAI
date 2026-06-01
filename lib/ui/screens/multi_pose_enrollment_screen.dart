import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../../core/camera_frame.dart';
import '../../core/enrollment_module/enrollment_module_interface.dart';
import '../../core/face_detection/face_detector_interface.dart';
import '../../core/face_preprocessor.dart';
import '../../core/recognition/multi_pose_enrollment_controller.dart';
import '../../models/face_pose.dart';

// One frame plus its head pose and validity, fed to the enrollment controller.
class PoseObservation {
  final CameraFrame frame;
  final double yaw; // headEulerAngleY
  final double pitch; // headEulerAngleX
  final bool valid; // single face, eyes open, landmarks present
  const PoseObservation({
    required this.frame,
    required this.yaw,
    required this.pitch,
    required this.valid,
  });
}

typedef PoseProvider = Stream<PoseObservation> Function();

/// Guided multi-pose enrollment (frontal → left → right → up → down). Collects
/// [framesPerPose] valid frames per target pose, then calls
/// [EnrollmentModuleInterface.enrollMultiPose] to build the template gallery.
class MultiPoseEnrollmentScreen extends StatefulWidget {
  final EnrollmentModuleInterface enrollmentModule;
  final EmployeeFormData? formData;

  /// Injectable pose source for tests; production uses the real camera +
  /// [faceDetector].
  final PoseProvider? poseProvider;
  final FaceDetectorInterface? faceDetector;
  final int framesPerPose;

  const MultiPoseEnrollmentScreen({
    super.key,
    required this.enrollmentModule,
    this.formData,
    this.poseProvider,
    this.faceDetector,
    this.framesPerPose = 5,
  });

  @override
  State<MultiPoseEnrollmentScreen> createState() =>
      _MultiPoseEnrollmentScreenState();
}

enum _Phase { capturing, processing, success, error }

class _MultiPoseEnrollmentScreenState extends State<MultiPoseEnrollmentScreen> {
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _green = Color(0xFF2E7D32);

  static const Map<FacePose, String> _instructions = {
    FacePose.frontal: 'Look Straight',
    FacePose.left: 'Turn Slightly Left',
    FacePose.right: 'Turn Slightly Right',
    FacePose.up: 'Look Up',
    FacePose.down: 'Look Down',
  };

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  late final MultiPoseEnrollmentController _controller =
      MultiPoseEnrollmentController(framesPerPose: widget.framesPerPose);

  EmployeeFormData? _formData;
  _Phase _phase = _Phase.capturing;
  String? _errorMessage;
  EnrollmentResult? _result;

  StreamSubscription<PoseObservation>? _poseSub;
  CameraController? _camera;
  CameraDescription? _cameraDescription;
  bool _cameraReady = false;
  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    _formData = widget.formData;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _formData ??=
        ModalRoute.of(context)?.settings.arguments as EmployeeFormData?;
    if (_phase == _Phase.capturing && _poseSub == null && !_cameraReady) {
      _start();
    }
  }

  @override
  void dispose() {
    _poseSub?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (widget.poseProvider != null) {
      setState(() => _cameraReady = true);
      _poseSub = widget.poseProvider!().listen(_onPose);
    } else {
      await _initCamera();
    }
  }

  // ── Pose handling (shared by test + device paths) ──────────────────────────
  void _onPose(PoseObservation obs) {
    if (_phase != _Phase.capturing) return;
    // Carry the measured angles on the frame for the [TemplateAudit] log.
    _controller.offer(obs.frame.copyWith(yaw: obs.yaw, pitch: obs.pitch),
        yaw: obs.yaw, pitch: obs.pitch, valid: obs.valid);
    if (!mounted) return;
    setState(() {});
    if (_controller.isComplete) _finish();
  }

  Future<void> _finish() async {
    if (_phase != _Phase.capturing) return;
    setState(() => _phase = _Phase.processing);
    await _poseSub?.cancel();
    _poseSub = null;
    await _camera?.stopImageStream();

    final form = _formData;
    if (form == null) {
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'Missing employee details.';
      });
      return;
    }
    try {
      final res =
          await widget.enrollmentModule.enrollMultiPose(form, _controller.buckets);
      if (!mounted) return;
      setState(() {
        _result = res;
        _phase = res.success ? _Phase.success : _Phase.error;
        _errorMessage = res.errorMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'Enrollment failed: $e';
      });
    }
  }

  // ── Device camera path ─────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(front, ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _camera = controller;
        _cameraDescription = front;
        _cameraReady = true;
      });
      controller.startImageStream(_handleImage);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _errorMessage = 'Camera initialisation failed: $e';
        });
      }
    }
  }

  Future<void> _handleImage(CameraImage image) async {
    if (_phase != _Phase.capturing || _detecting) return;
    final detector = widget.faceDetector;
    if (detector == null) return;
    _detecting = true;
    try {
      final frame = _enrich(image);
      final faces = await detector.detect(frame);
      if (!mounted || _phase != _Phase.capturing) return;
      if (faces.length != 1) {
        setState(() {}); // keep guidance visible
        return;
      }
      final f = faces.first;
      // Quality gate WITHOUT the head-pose gate (multi-pose is off-frontal).
      final eyesOpen = (f.leftEyeOpenProbability ?? 1.0) >= 0.60 &&
          (f.rightEyeOpenProbability ?? 1.0) >= 0.60;
      final landmarks = f.leftEyePosition != null &&
          f.rightEyePosition != null &&
          f.noseBasePosition != null &&
          f.mouthLeftPosition != null &&
          f.mouthRightPosition != null;
      final enriched = frame.copyWith(
        faceCount: 1,
        faceBox: FaceBoxData(
            left: f.box.left,
            top: f.box.top,
            width: f.box.width,
            height: f.box.height),
        leftEye: f.leftEyePosition,
        rightEye: f.rightEyePosition,
        noseBase: f.noseBasePosition,
        mouthLeft: f.mouthLeftPosition,
        mouthRight: f.mouthRightPosition,
      );
      _onPose(PoseObservation(
        frame: enriched,
        yaw: f.headEulerAngleY ?? 0.0,
        pitch: f.headEulerAngleX ?? 0.0,
        valid: eyesOpen && landmarks,
      ));
    } catch (e) {
      debugPrint('[MultiPoseEnroll] $e');
    } finally {
      _detecting = false;
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

  CameraFrame _enrich(CameraImage image) {
    final p = image.planes.first;
    final rgb = FacePreprocessor.nv21ToRgb(p.bytes, image.width, image.height,
        bytesPerRow: p.bytesPerRow);
    return CameraFrame(
      bytes: p.bytes,
      width: image.width,
      height: image.height,
      sharpnessScore: 50.0,
      rgbBytes: rgb,
      nv21Bytes: p.bytes,
      nv21BytesPerRow: p.bytesPerRow,
      rotationDegrees: _rotationDegrees(),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('multi_pose_enrollment_screen'),
      backgroundColor: _deepBlue,
      appBar: AppBar(
        backgroundColor: _deepBlue,
        elevation: 0,
        title: const Text('Face Enrollment',
            style: TextStyle(color: _white, fontWeight: FontWeight.w600)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: _white),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.processing:
        return const Center(
          child: CircularProgressIndicator(
            key: Key('enroll_processing'),
            valueColor: AlwaysStoppedAnimation<Color>(_saffron),
          ),
        );
      case _Phase.success:
        return _successView();
      case _Phase.error:
        return _errorView();
      case _Phase.capturing:
        return _captureView();
    }
  }

  Widget _captureView() {
    final pose = _controller.currentPose ?? FacePose.frontal;
    final instruction = _instructions[pose] ?? 'Look Straight';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _saffron, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: (_camera != null && _camera!.value.isInitialized)
                  ? CameraPreview(_camera!)
                  : const Center(
                      child: Icon(Icons.face_retouching_natural,
                          color: _white, size: 64)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            instruction,
            key: const Key('pose_instruction'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Pose ${_controller.posesCompleted + 1}/${_controller.totalPoses}',
            key: const Key('pose_progress'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _saffron, fontSize: 16),
          ),
          Text(
            'Frames ${_controller.collectedForCurrentPose}/${widget.framesPerPose}',
            key: const Key('frame_progress'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _white.withValues(alpha: 0.7), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _successView() {
    final count = _result?.record?.templates?.length ?? 0;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified, color: _green, size: 72),
          const SizedBox(height: 16),
          const Text('Enrollment Successful',
              key: Key('enrollment_success'),
              style: TextStyle(
                  color: _green, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('$count pose templates stored',
              key: const Key('template_count'),
              style: TextStyle(color: _white.withValues(alpha: 0.8))),
          const SizedBox(height: 28),
          ElevatedButton(
            key: const Key('return_home_button'),
            onPressed: () => Navigator.of(context)
                .pushNamedAndRemoveUntil('/home', (_) => false),
            style: ElevatedButton.styleFrom(
                backgroundColor: _saffron, foregroundColor: _white),
            child: const Text('Return to Home'),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFD32F2F), size: 64),
            const SizedBox(height: 16),
            Text(_errorMessage ?? 'Enrollment failed. Please retry.',
                key: const Key('enroll_error'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _white)),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const Key('return_home_button'),
              onPressed: () => Navigator.of(context)
                  .pushNamedAndRemoveUntil('/home', (_) => false),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _saffron, foregroundColor: _white),
              child: const Text('Return to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
