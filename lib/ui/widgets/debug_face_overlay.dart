import 'package:flutter/material.dart';

/// TEMPORARY debug overlay: draws green rectangles around detected faces and
/// prints raw detector values on screen. Used only on the camera screens when a
/// real face detector is active, to visually confirm whether ML Kit is
/// returning faces (and where). Remove once detection is verified on-device.
class DebugFaceOverlay extends StatelessWidget {
  /// One rect per detected face, in NORMALIZED image coordinates (0..1).
  final List<Rect> normalizedBoxes;

  /// Human-readable dump of the latest detector values.
  final String info;

  const DebugFaceOverlay({
    super.key,
    required this.normalizedBoxes,
    required this.info,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _BoxPainter(normalizedBoxes)),
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Container(
              key: const Key('debug_face_info'),
              padding: const EdgeInsets.all(8),
              color: Colors.black.withValues(alpha: 0.6),
              child: Text(
                info,
                style: const TextStyle(
                  color: Color(0xFF00FF00),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  final List<Rect> normalized;
  _BoxPainter(this.normalized);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00FF00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final r in normalized) {
      canvas.drawRect(
        Rect.fromLTWH(
          r.left * size.width,
          r.top * size.height,
          r.width * size.width,
          r.height * size.height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) =>
      old.normalized != normalized;
}
