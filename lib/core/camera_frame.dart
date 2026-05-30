class CameraFrame {
  final List<int> bytes;
  final int width;
  final int height;
  final double sharpnessScore;

  /// Optional eye landmark coordinates for liveness detection.
  ///
  /// When populated (e.g., by a MediaPipe / ML Kit face detector), this field
  /// holds exactly 6 two-element `[x, y]` lists corresponding to the six eye
  /// landmark points (p1–p6) used to compute the Eye Aspect Ratio.
  ///
  /// Frames without landmark data (e.g., no face detected) leave this `null`.
  final List<List<double>>? landmarks;

  /// Full-frame RGB888 pixel data (3 bytes/pixel, row-major), produced by the
  /// camera screen via YUV420→RGB conversion. When present together with
  /// [faceBox], the model runner crops and resizes the face region from this
  /// instead of treating [bytes] as whole-frame RGB. Optional (default null).
  final List<int>? rgbBytes;

  /// NV21-encoded frame bytes for the ML Kit face detector. Optional.
  final List<int>? nv21Bytes;

  /// Row stride (bytes per row) of the NV21 Y plane, for ML Kit metadata.
  /// Null → callers default to [width].
  final int? nv21BytesPerRow;

  /// Camera sensor rotation in degrees (0/90/180/270) for the detector. Default 0.
  final int rotationDegrees;

  /// Detected face region in [rgbBytes] pixel coordinates. Optional.
  final FaceBoxData? faceBox;

  /// Left/right eye centre `[x, y]` in [rgbBytes] pixel coordinates, used for
  /// similarity-transform face alignment. Optional (null → square-crop fallback).
  final List<double>? leftEye;
  final List<double>? rightEye;

  /// Number of faces detected in this frame. Defaults to 1 so existing callers
  /// (and tests) behave as a single-face frame; the camera screen sets the real
  /// count so the auth engine can fail on 0 or >1 faces.
  final int faceCount;

  const CameraFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.sharpnessScore,
    this.landmarks,
    this.rgbBytes,
    this.nv21Bytes,
    this.nv21BytesPerRow,
    this.rotationDegrees = 0,
    this.faceBox,
    this.leftEye,
    this.rightEye,
    this.faceCount = 1,
  });

  CameraFrame copyWith({
    List<List<double>>? landmarks,
    List<int>? rgbBytes,
    List<int>? nv21Bytes,
    int? nv21BytesPerRow,
    int? rotationDegrees,
    FaceBoxData? faceBox,
    List<double>? leftEye,
    List<double>? rightEye,
    int? faceCount,
  }) =>
      CameraFrame(
        bytes: bytes,
        width: width,
        height: height,
        sharpnessScore: sharpnessScore,
        landmarks: landmarks ?? this.landmarks,
        rgbBytes: rgbBytes ?? this.rgbBytes,
        nv21Bytes: nv21Bytes ?? this.nv21Bytes,
        nv21BytesPerRow: nv21BytesPerRow ?? this.nv21BytesPerRow,
        rotationDegrees: rotationDegrees ?? this.rotationDegrees,
        faceBox: faceBox ?? this.faceBox,
        leftEye: leftEye ?? this.leftEye,
        rightEye: rightEye ?? this.rightEye,
        faceCount: faceCount ?? this.faceCount,
      );
}

/// Lightweight bounding-box value type carried on a [CameraFrame].
///
/// Mirrors `FaceBox` from the face_detection layer but lives here to avoid a
/// dependency cycle (camera_frame is a leaf type imported everywhere).
class FaceBoxData {
  final int left;
  final int top;
  final int width;
  final int height;

  const FaceBoxData({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}
