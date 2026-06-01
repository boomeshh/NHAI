import 'face_embedding.dart';
import 'face_pose.dart';

// One enrolled face template: a pose-labelled, averaged embedding plus the
// metadata needed for gallery matching, quality auditing and migration.
class FaceTemplate {
  final FaceEmbedding embedding;
  final FacePose poseLabel;
  final double yaw;
  final double pitch;
  final double qualityScore;
  final DateTime createdAt;
  final int pipelineVersion;

  const FaceTemplate({
    required this.embedding,
    required this.poseLabel,
    required this.yaw,
    required this.pitch,
    required this.qualityScore,
    required this.createdAt,
    required this.pipelineVersion,
  });

  Map<String, dynamic> toJson() => {
        'embedding': embedding.toJson(),
        'poseLabel': poseLabel.label,
        'yaw': yaw,
        'pitch': pitch,
        'qualityScore': qualityScore,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'pipelineVersion': pipelineVersion,
      };

  factory FaceTemplate.fromJson(Map<String, dynamic> json) => FaceTemplate(
        embedding:
            FaceEmbedding.fromJson(json['embedding'] as Map<String, dynamic>),
        poseLabel: FacePoseX.fromLabel(json['poseLabel'] as String),
        yaw: (json['yaw'] as num).toDouble(),
        pitch: (json['pitch'] as num).toDouble(),
        qualityScore: (json['qualityScore'] as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        pipelineVersion: (json['pipelineVersion'] as num?)?.toInt() ?? 0,
      );
}
