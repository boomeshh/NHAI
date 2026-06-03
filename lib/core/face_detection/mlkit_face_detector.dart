import 'dart:math' show Point;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' show Size;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../camera_frame.dart';
import 'detection_forensics.dart';
import 'face_detector_interface.dart';
import 'landmark_audit.dart';

/// Maps a rotation in degrees (0/90/180/270) to ML Kit's [InputImageRotation].
/// Pure function (no native init) so it is unit-testable.
InputImageRotation mlkitRotationFromDegrees(int deg) {
  switch (deg % 360) {
    case 90:
      return InputImageRotation.rotation90deg;
    case 180:
      return InputImageRotation.rotation180deg;
    case 270:
      return InputImageRotation.rotation270deg;
    default:
      return InputImageRotation.rotation0deg;
  }
}

/// Real face detector backed by Google ML Kit.
///
/// Device-only: ML Kit uses a native platform channel and is never constructed
/// in unit/widget tests. Consumes [CameraFrame.nv21Bytes] + [rotationDegrees].
class MlKitFaceDetector implements FaceDetectorInterface {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableContours: true, // needed to derive 6-point eye landmarks for EAR
      enableLandmarks: true,
      enableClassification: true, // exposes eye-open / smiling probabilities
      enableTracking: true,
      minFaceSize: 0.1, // accept smaller faces than the 0.15 default
    ),
  );

  @override
  Future<List<DetectedFace>> detect(CameraFrame frame) async {
    final nv21 = frame.nv21Bytes;
    if (nv21 == null) {
      debugPrint('[MlKitFaceDetector] SKIP: nv21Bytes is null');
      return const [];
    }

    final rotation = mlkitRotationFromDegrees(frame.rotationDegrees);
    final int bytesPerRow = frame.nv21BytesPerRow ?? frame.width;
    // TEMP DIAGNOSTICS: input metadata for every frame.
    debugPrint(
      '[MlKitFaceDetector] processImage CALLED w=${frame.width} h=${frame.height} '
      'rotationDeg=${frame.rotationDegrees} rotation=$rotation '
      'bytesPerRow=$bytesPerRow nv21Len=${nv21.length} '
      '(expected≈${(frame.height * bytesPerRow * 1.5).round()})',
    );

    final input = InputImage.fromBytes(
      bytes: nv21 is Uint8List ? nv21 : Uint8List.fromList(nv21),
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: bytesPerRow,
      ),
    );

    final List<Face> faces;
    try {
      faces = await _detector.processImage(input);
    } catch (e) {
      // Surface conversion/detection errors instead of silently yielding 0.
      debugPrint('[MlKitFaceDetector] ERROR processImage: $e');
      return const [];
    }

    // ── Phase 1 — detection forensics (structured, greppable) ─────────────────
    const auditor = LandmarkAuditor();
    for (var i = 0; i < faces.length; i++) {
      final f = faces[i];
      final r = f.boundingBox;
      List<double>? lm(FaceLandmarkType t) => _landmarkXy(f, t);
      final audit = auditor.audit(
        hasLeftEye: f.landmarks[FaceLandmarkType.leftEye] != null,
        hasRightEye: f.landmarks[FaceLandmarkType.rightEye] != null,
        hasNose: f.landmarks[FaceLandmarkType.noseBase] != null,
        hasMouthLeft: f.landmarks[FaceLandmarkType.leftMouth] != null,
        hasMouthRight: f.landmarks[FaceLandmarkType.rightMouth] != null,
      );
      DetectionForensics.logFrame(
        faces: faces.length,
        boxLeft: r.left.round(),
        boxTop: r.top.round(),
        boxWidth: r.width.round(),
        boxHeight: r.height.round(),
        rotation: frame.rotationDegrees,
        frameWidth: frame.width,
        frameHeight: frame.height,
        leftEye: lm(FaceLandmarkType.leftEye),
        rightEye: lm(FaceLandmarkType.rightEye),
        nose: lm(FaceLandmarkType.noseBase),
        mouthLeft: lm(FaceLandmarkType.leftMouth),
        mouthRight: lm(FaceLandmarkType.rightMouth),
        yaw: f.headEulerAngleY,
        pitch: f.headEulerAngleX,
        roll: f.headEulerAngleZ,
        leftEyeOpen: f.leftEyeOpenProbability,
        rightEyeOpen: f.rightEyeOpenProbability,
        audit: audit,
      );
    }
    if (faces.isEmpty) {
      debugPrint(DetectionForensics.detection(
        faces: 0,
        boxLeft: 0,
        boxTop: 0,
        boxWidth: 0,
        boxHeight: 0,
        rotation: frame.rotationDegrees,
        frameWidth: frame.width,
        frameHeight: frame.height,
      ));
      debugPrint(
          DetectionForensics.decision(accepted: false, reason: 'noFace'));
    }

    return faces.map((f) {
      final r = f.boundingBox;
      return DetectedFace(
        box: FaceBox(
          left: r.left.round(),
          top: r.top.round(),
          width: r.width.round(),
          height: r.height.round(),
        ),
        eyeLandmarks: _earPoints(f),
        leftEyeOpenProbability: f.leftEyeOpenProbability,
        rightEyeOpenProbability: f.rightEyeOpenProbability,
        headEulerAngleY: f.headEulerAngleY,
        headEulerAngleZ: f.headEulerAngleZ,
        headEulerAngleX: f.headEulerAngleX,
        hasLeftEye: f.landmarks[FaceLandmarkType.leftEye] != null,
        hasRightEye: f.landmarks[FaceLandmarkType.rightEye] != null,
        hasNoseBase: f.landmarks[FaceLandmarkType.noseBase] != null,
        hasLeftCheek: f.landmarks[FaceLandmarkType.leftCheek] != null,
        hasRightCheek: f.landmarks[FaceLandmarkType.rightCheek] != null,
        leftEyePosition: _landmarkXy(f, FaceLandmarkType.leftEye),
        rightEyePosition: _landmarkXy(f, FaceLandmarkType.rightEye),
        noseBasePosition: _landmarkXy(f, FaceLandmarkType.noseBase),
        mouthLeftPosition: _landmarkXy(f, FaceLandmarkType.leftMouth),
        mouthRightPosition: _landmarkXy(f, FaceLandmarkType.rightMouth),
      );
    }).toList();
  }

  static List<double>? _landmarkXy(Face f, FaceLandmarkType type) {
    final lm = f.landmarks[type];
    if (lm == null) return null;
    return [lm.position.x.toDouble(), lm.position.y.toDouble()];
  }

  /// Derives 6 approximate EAR landmark points (p1–p6) from the left-eye contour.
  List<List<double>>? _earPoints(Face f) {
    final contour = f.contours[FaceContourType.leftEye];
    final pts = contour?.points;
    if (pts == null || pts.length < 6) return null;
    final sorted = [...pts]..sort((a, b) => a.x.compareTo(b.x));
    final p1 = sorted.first;
    final p4 = sorted.last;
    final mid = sorted.sublist(1, sorted.length - 1)
      ..sort((a, b) => a.y.compareTo(b.y));
    final upper = mid.first;
    final upper2 = mid.length > 1 ? mid[1] : mid.first;
    final lower = mid.last;
    final lower2 = mid.length > 1 ? mid[mid.length - 2] : mid.last;
    List<double> pt(Point<int> p) => [p.x.toDouble(), p.y.toDouble()];
    return [pt(p1), pt(upper), pt(upper2), pt(p4), pt(lower2), pt(lower)];
  }

  @override
  void dispose() {
    _detector.close();
  }
}
