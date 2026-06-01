import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/auth_engine/auth_engine_impl.dart';
import '../../core/auth_engine/auth_engine_interface.dart';
import '../../core/camera_frame.dart';
import '../../core/enrollment_module/enrollment_module_interface.dart';
import '../../core/recognition/gallery_audit.dart';
import '../../core/recognition/pose_classifier.dart';
import '../../core/recognition/recognition_validator.dart';
import '../../models/employee_record.dart';
import '../../models/face_pose.dart';
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
  final PoseProvider poseProvider; // camera on device; injected in tests
  final int framesPerEnrollPose;
  final int verifyBatchSize;
  final int verifyAttempts;

  const RecognitionValidationScreen({
    super.key,
    required this.enrollmentModule,
    required this.authEngine,
    required this.formData,
    required this.poseProvider,
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

  ValidationReport? _report;
  String? _csvPath;

  double get _threshold => AuthEngineImpl.defaultVerificationThreshold;

  @override
  void initState() {
    super.initState();
    _sub = widget.poseProvider().listen(_onPose);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
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
      _galleryPairs =
          GalleryAudit.pairwiseCosines(res.record!.templates ?? const []);
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
      // Best pose for display only (read-only gallery audit).
      FacePose? bestPose;
      try {
        final emb = await widget.authEngine.extractEmbedding(batch.last);
        bestPose = GalleryAudit.bestPose(
            GalleryAudit.scoreTemplates(emb.vector, _record!));
      } catch (_) {}
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
    final report =
        RecognitionValidator(_threshold).analyze(_attempts, galleryPairs: _galleryPairs);
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
          _statRow('Success Rate', '${(r.successRate * 100).round()}%'),
          const SizedBox(height: 12),
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
