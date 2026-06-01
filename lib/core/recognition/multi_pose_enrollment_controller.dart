import '../../models/face_pose.dart';
import '../camera_frame.dart';
import 'pose_classifier.dart';
import 'stable_embedding_collector.dart';

// Drives guided multi-pose enrollment: walks the pose sequence, and for the
// current target pose collects [framesPerPose] valid frames (frames must pass
// quality gates AND fall in the target pose window). Pure / unit-testable; the
// camera screen feeds it frames and renders [currentPose] guidance.
class MultiPoseEnrollmentController {
  final List<FacePose> sequence;
  final int framesPerPose;

  final Map<FacePose, List<CameraFrame>> _buckets = {};
  int _index = 0;
  StableEmbeddingCollector<CameraFrame> _collector;

  MultiPoseEnrollmentController({
    this.framesPerPose = 5,
    List<FacePose>? sequence,
  })  : sequence = sequence ?? PoseClassifier.enrollmentSequence,
        _collector = StableEmbeddingCollector<CameraFrame>(target: framesPerPose) {
    _collector.arm();
  }

  FacePose? get currentPose => isComplete ? null : sequence[_index];
  bool get isComplete => _index >= sequence.length;
  int get collectedForCurrentPose => _collector.count;
  int get posesCompleted => _index;
  int get totalPoses => sequence.length;
  Map<FacePose, List<CameraFrame>> get buckets =>
      Map<FacePose, List<CameraFrame>>.unmodifiable(_buckets);

  /// Offers a frame for the CURRENT target pose. [valid] = passed the quality
  /// gates (eyes-open, not occluded, single face). Returns true if collected.
  /// Advances to the next pose once [framesPerPose] are gathered.
  bool offer(
    CameraFrame frame, {
    required double yaw,
    required double pitch,
    required bool valid,
  }) {
    if (isComplete) return false;
    final pose = sequence[_index];
    final inPose = valid && PoseClassifier.matches(pose, yaw, pitch);
    final collected = _collector.offer(frame, valid: inPose);
    if (_collector.isComplete) {
      _buckets[pose] = _collector.items.toList();
      _index++;
      _collector = StableEmbeddingCollector<CameraFrame>(target: framesPerPose)
        ..arm();
    }
    return collected;
  }

  void reset() {
    _buckets.clear();
    _index = 0;
    _collector = StableEmbeddingCollector<CameraFrame>(target: framesPerPose)
      ..arm();
  }
}
