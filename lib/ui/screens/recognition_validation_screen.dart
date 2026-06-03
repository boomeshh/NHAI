import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../../core/auth_engine/auth_engine_impl.dart';
import '../../core/auth_engine/auth_engine_interface.dart';
import '../../core/camera_frame.dart';
import '../../core/enrollment_module/enrollment_module_interface.dart';
import '../../core/face_detection/face_detector_interface.dart';
import '../../core/face_preprocessor.dart';
import '../../core/recognition/embedding_variance_analyzer.dart';
import '../../core/recognition/enrollment_audit.dart';
import '../../core/recognition/gallery_audit.dart';
import '../../core/recognition/pose_classifier.dart';
import '../../core/recognition/recognition_validator.dart';
import '../../models/employee_record.dart';
import '../../models/face_pose.dart';
import '../../models/face_template.dart';
import 'multi_pose_enrollment_screen.dart' show PoseObservation, PoseProvider;

// TEMPORARY Recognition Validation Screen. Fresh-enrolls one employee from the
// injected pose stream, then runs N automatic verification attempts and reports
// per-attempt Best Pose / Similarity / Pass-Fail, aggregate stats, a CSV
// report, and the single most-likely root-cause subsystem. Read-only: no
// changes to matcher/threshold/gallery/alignment/attendance.
class RecognitionValidationScreen extends StatefulWidget {
  final EnrollmentModuleInterface enrollmentModule;
  final AuthEngineInterface authEngine;
  final EmployeeFormData formData;

  /// Injected pose source for tests. When null, the screen uses the real
  /// front camera + [faceDetector] (device).
  final PoseProvider? poseProvider;
  final FaceDetectorInterface? faceDetector;
  final int framesPerEnrollPose;
  final int verifyBatchSize;
  final int verifyAttempts;

  const RecognitionValidationScreen({
    super.key,
    required this.enrollmentModule,
    required this.authEngine,
    required this.formData,
    this.poseProvider,
    this.faceDetector,
    this.framesPerEnrollPose = 5,
    this.verifyBatchSize = 5,
    this.verifyAttempts = 10,
  });

  @override
  State<RecognitionValidationScreen> createState() =>
      _RecognitionValidationScreenState();
}

enum _Phase { enrolling, verifying, done, error }

class _RecognitionValidationScreenState
    extends State<RecognitionValidationScreen> {
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _green = Color(0xFF2E7D32);
  static const Color _red = Color(0xFFC62828);

  _Phase _phase = _Phase.enrolling;
  String _status = 'Enrolling… look straight, then turn slightly each way';
  StreamSubscription<PoseObservation>? _sub;
  bool _busy = false;

  final Map<FacePose, List<CameraFrame>> _enrollBuckets = {};
  EmployeeRecord? _record;
  Map<String, double> _galleryPairs = const {};

  final List<CameraFrame> _verifyBatch = [];
  final List<({FacePose? bestPose, double similarity})> _attempts = [];

  // ── Recognition-quality forensics (read-only) ──────────────────────────────
  static const EmbeddingVarianceAnalyzer _varianceAnalyzer =
      EmbeddingVarianceAnalyzer();
  final List<EmbeddingVarianceReport> _variances = [];
  final List<double> _perFrameMatches = [];
  EnrollmentAuditReport? _enrollAudit;
  VarianceVerdict? _verdict;

  ValidationReport? _report;
  String? _csvPath;

  // Device camera (used when poseProvider is null).
  CameraController? _camera;
  CameraDescription? _cameraDescription;
  bool _detecting = false;

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  double get _threshold => AuthEngineImpl.defaultVerificationThreshold;

  @override
  void initState() {
    super.initState();
    if (widget.poseProvider != null) {
      _sub = widget.poseProvider!().listen(_onPose);
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

  // ── Device camera → PoseObservation (mirrors the enrollment/auth screens) ──
  Future<void> _initCamera() async {
    final detector = widget.faceDetector;
    if (detector == null) {
      _fail('No camera/detector available');
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
      _fail('Camera initialisation failed: $e');
    }
  }

  Future<void> _handleImage(CameraImage image) async {
    if (_detecting || _busy || _phase == _Phase.done || _phase == _Phase.error) {
      return;
    }
    final detector = widget.faceDetector;
    if (detector == null) return;
    _detecting = true;
    try {
      final p = image.planes.first;
      final rgb = FacePreprocessor.nv21ToRgb(
          p.bytes, image.width, image.height, bytesPerRow: p.bytesPerRow);
      final base = CameraFrame(
        bytes: p.bytes,
        width: image.width,
        height: image.height,
        sharpnessScore: 50.0,
        rgbBytes: rgb,
        nv21Bytes: p.bytes,
        nv21BytesPerRow: p.bytesPerRow,
        rotationDegrees: _rotationDegrees(),
      );
      final faces = await detector.detect(base);
      if (!mounted || faces.length != 1) return;
      final f = faces.first;
      final eyesOpen = (f.leftEyeOpenProbability ?? 1.0) >= 0.60 &&
          (f.rightEyeOpenProbability ?? 1.0) >= 0.60;
      final has5 = f.leftEyePosition != null &&
          f.rightEyePosition != null &&
          f.noseBasePosition != null &&
          f.mouthLeftPosition != null &&
          f.mouthRightPosition != null;
      final enriched = base.copyWith(
        faceCount: 1,
        faceBox: FaceBoxData(
            left: f.box.left, top: f.box.top, width: f.box.width, height: f.box.height),
        leftEye: f.leftEyePosition,
        rightEye: f.rightEyePosition,
        noseBase: f.noseBasePosition,
        mouthLeft: f.mouthLeftPosition,
        mouthRight: f.mouthRightPosition,
      );
      await _onPose(PoseObservation(
        frame: enriched,
        yaw: f.headEulerAngleY ?? 0.0,
        pitch: f.headEulerAngleX ?? 0.0,
        valid: eyesOpen && has5,
      ));
    } catch (e) {
      debugPrint('[RecognitionValidation] $e');
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

  Future<void> _onPose(PoseObservation obs) async {
    if (_busy || _phase == _Phase.done || _phase == _Phase.error) return;
    if (!obs.valid) return;

    if (_phase == _Phase.enrolling) {
      final pose = PoseClassifier.classify(obs.yaw, obs.pitch) ?? FacePose.frontal;
      final bucket = _enrollBuckets.putIfAbsent(pose, () => []);
      if (bucket.length < widget.framesPerEnrollPose) {
        bucket.add(obs.frame.copyWith(yaw: obs.yaw, pitch: obs.pitch));
      }
      setState(() => _status =
          'Enrolling… captured ${_enrollBuckets.values.fold(0, (a, b) => a + b.length)} frames');
      // Enroll once the frontal pose has enough frames.
      final frontal = _enrollBuckets[FacePose.frontal];
      if (frontal != null && frontal.length >= widget.framesPerEnrollPose) {
        await _finishEnroll();
      }
    } else if (_phase == _Phase.verifying) {
      _verifyBatch.add(obs.frame.copyWith(yaw: obs.yaw, pitch: obs.pitch));
      if (_verifyBatch.length >= widget.verifyBatchSize) {
        await _runAttempt(List<CameraFrame>.from(_verifyBatch));
        _verifyBatch.clear();
      }
    }
  }

  Future<void> _finishEnroll() async {
    _busy = true;
    try {
      final res = await widget.enrollmentModule
          .enrollMultiPose(widget.formData, _enrollBuckets);
      if (!res.success || res.record == null) {
        _fail(res.errorMessage ?? 'Enrollment failed');
        return;
      }
      _record = res.record;
      final templates = res.record!.templates ?? const <FaceTemplate>[];
      _galleryPairs = GalleryAudit.pairwiseCosines(templates);
      // Task 2 — enrollment audit (magnitudes + pairwise) logged once.
      _enrollAudit = EnrollmentAudit.audit(templates);
      debugPrint(_enrollAudit!.toLog());
      setState(() {
        _phase = _Phase.verifying;
        _status = 'Verifying… attempt 1/${widget.verifyAttempts}';
      });
    } catch (e) {
      _fail('Enrollment error: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _runAttempt(List<CameraFrame> batch) async {
    _busy = true;
    try {
      // Authoritative decision via the unchanged engine (logs [MatcherAudit] /
      // [Recognition] / [Decision]).
      final result = await widget.authEngine.authenticateAveraged(batch);

      // Task 1 — intra-attempt variance: extract each live frame's embedding
      // (read-only; the engine already does this internally for averaging) and
      // measure how consistent the embedder is on identical input.
      final liveEmbs = <List<double>>[];
      for (final f in batch) {
        try {
          liveEmbs.add((await widget.authEngine.extractEmbedding(f)).vector);
        } catch (_) {}
      }
      final variance = _varianceAnalyzer.analyze(liveEmbs);
      _variances.add(variance);
      debugPrint(variance.toLog());

      // Per-frame match BEFORE averaging (vs the gallery) to test the averaging
      // step against the raw frames.
      final tmplVecs = (_record!.templates ?? const <FaceTemplate>[])
          .map((t) => t.embedding.vector)
          .toList();
      if (liveEmbs.isNotEmpty && tmplVecs.isNotEmpty) {
        final perFrame = liveEmbs
                .map((e) => bestGalleryCosine(e, tmplVecs))
                .reduce((a, b) => a + b) /
            liveEmbs.length;
        _perFrameMatches.add(perFrame);
        debugPrint('[EmbeddingVariance] perFrameMatchAvg='
            '${perFrame.toStringAsFixed(3)} averagedMatch='
            '${result.trustScore.toStringAsFixed(3)}');
      }

      // Best pose for display only (read-only gallery audit).
      FacePose? bestPose;
      if (liveEmbs.isNotEmpty) {
        final scores = GalleryAudit.scoreTemplates(liveEmbs.last, _record!);
        bestPose = GalleryAudit.bestPose(scores);
        // Task 5 — ranked similarities of this (near-frontal) probe vs every
        // stored template, highest first.
        final ranked = scores.where((s) => s.score != null).toList()
          ..sort((a, b) => b.score!.compareTo(a.score!));
        debugPrint('[FrontalProbeRanking] ${ranked.map((s) => '${s.pose.label}=${s.score!.toStringAsFixed(2)}').join(' ')}');
      }
      _attempts.add((bestPose: bestPose, similarity: result.trustScore));
      if (_attempts.length >= widget.verifyAttempts) {
        await _finish();
      } else {
        setState(() => _status =
            'Verifying… attempt ${_attempts.length + 1}/${widget.verifyAttempts}');
      }
    } catch (e) {
      _fail('Verification error: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _finish() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _camera?.stopImageStream();
    } catch (_) {}
    final report =
        RecognitionValidator(_threshold).analyze(_attempts, galleryPairs: _galleryPairs);

    // Task 4 — attribute the variance to model / enrollment / averaging.
    final liveIntraAvg = _variances.isEmpty
        ? 1.0
        : _variances.map((v) => v.avg).reduce((a, b) => a + b) /
            _variances.length;
    final perFrameMatchAvg = _perFrameMatches.isEmpty
        ? report.avgSimilarity
        : _perFrameMatches.reduce((a, b) => a + b) / _perFrameMatches.length;
    _verdict = VarianceAttribution.attribute(
      liveIntraAvg: liveIntraAvg,
      enrollPairs: _galleryPairs,
      perFrameMatchAvg: perFrameMatchAvg,
      averagedMatch: report.avgSimilarity,
    );
    debugPrint('[VarianceVerdict] source=${_verdict!.source.name} '
        'liveIntraAvg=${liveIntraAvg.toStringAsFixed(3)} '
        'perFrameMatchAvg=${perFrameMatchAvg.toStringAsFixed(3)} '
        'averagedMatch=${report.avgSimilarity.toStringAsFixed(3)} '
        '— ${_verdict!.explanation}');

    String? path;
    try {
      final f = File('${Directory.systemTemp.path}/recognition_validation.csv');
      await f.writeAsString(report.toCsv());
      path = f.path;
    } catch (_) {}
    debugPrint('[RecognitionValidation] CSV:\n${report.toCsv()}');
    setState(() {
      _report = report;
      _csvPath = path;
      _phase = _Phase.done;
    });
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _status = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('recognition_validation_screen'),
      backgroundColor: _deepBlue,
      appBar: AppBar(
        backgroundColor: _deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: _white),
        title: const Text('Recognition Validation',
            style: TextStyle(color: _white, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SafeArea(child: _report == null ? _progressView() : _resultView()),
    );
  }

  Widget _progressView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_phase != _Phase.error)
              const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_saffron)),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_status,
                  key: const Key('validation_status'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _phase == _Phase.error ? _red : _white,
                      fontSize: 15)),
            ),
          ],
        ),
      );

  String get _liveIntraAvgStr => _variances.isEmpty
      ? '—'
      : (_variances.map((v) => v.avg).reduce((a, b) => a + b) / _variances.length)
          .toStringAsFixed(3);

  String get _perFrameAvgStr => _perFrameMatches.isEmpty
      ? '—'
      : (_perFrameMatches.reduce((a, b) => a + b) / _perFrameMatches.length)
          .toStringAsFixed(3);

  Widget _resultView() {
    final r = _report!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statRow('Average Similarity', r.avgSimilarity.toStringAsFixed(3)),
          _statRow('Min', r.minSimilarity.toStringAsFixed(3)),
          _statRow('Max', r.maxSimilarity.toStringAsFixed(3)),
          _statRow('Std Deviation', r.stdDevSimilarity.toStringAsFixed(4)),
          _statRow('Success Rate', '${(r.successRate * 100).round()}%'),
          const Divider(color: _white),
          // ── Recognition-quality forensics ────────────────────────────────
          _statRow('Live Frame Consistency', _liveIntraAvgStr),
          _statRow('Per-frame Match (pre-avg)', _perFrameAvgStr),
          if (_enrollAudit != null) ...[
            _statRow('Enrolled Templates', '${_enrollAudit!.templates.length}'),
            _statRow('Templates Unit-Norm', '${_enrollAudit!.allUnitNormalized}'),
            _statRow('Gallery Degenerate', '${_enrollAudit!.anyDegenerate}'),
            _statRow('Gallery Over-divergent', '${_enrollAudit!.anyOverDivergent}'),
          ],
          const SizedBox(height: 12),
          if (_verdict != null)
            Container(
              key: const Key('variance_verdict'),
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _red),
              ),
              child: Text(
                  'VARIANCE SOURCE: ${_verdict!.source.name.toUpperCase()}\n\n'
                  '${_verdict!.explanation}',
                  style: const TextStyle(color: _white, fontSize: 13)),
            ),
          Container(
            key: const Key('validation_verdict'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _saffron.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _saffron),
            ),
            child: Text('ROOT CAUSE: ${r.culprit.name.toUpperCase()}\n\n${r.verdict}',
                style: const TextStyle(color: _white, fontSize: 13)),
          ),
          const SizedBox(height: 16),
          const Text('Attempt | Best Pose | Similarity | Result',
              style: TextStyle(color: _saffron, fontWeight: FontWeight.w700)),
          const Divider(color: _white),
          ...r.attempts.map((a) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 50, child: Text('#${a.attempt}', style: const TextStyle(color: _white))),
                    Expanded(child: Text(a.bestPose?.label ?? '—', style: const TextStyle(color: _white))),
                    SizedBox(width: 70, child: Text(a.similarity.toStringAsFixed(3), style: const TextStyle(color: _white))),
                    SizedBox(
                      width: 56,
                      child: Text(a.pass ? 'PASS' : 'FAIL',
                          style: TextStyle(
                              color: a.pass ? _green : _red,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 12),
          if (_csvPath != null)
            Text('CSV saved: $_csvPath',
                style: TextStyle(color: _white.withValues(alpha: 0.6), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _statRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: _white)),
            Text(v, style: const TextStyle(color: _saffron, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
