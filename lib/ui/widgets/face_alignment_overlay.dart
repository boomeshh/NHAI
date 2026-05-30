import 'package:flutter/material.dart';

/// Overlay widget that draws a face-alignment guide on top of the camera
/// viewfinder.
///
/// The guide is an oval cutout with a border whose color changes based on
/// whether a face has been detected within the guide area:
///   - [FaceAlignmentState.idle]     → white/neutral border
///   - [FaceAlignmentState.detected] → green border (Requirement 4.2)
///   - [FaceAlignmentState.timeout]  → amber/warning border
///
/// The widget is purely presentational; the parent screen is responsible for
/// updating [state] based on face-detection results.
///
/// Requirements: 4.1, 4.2
class FaceAlignmentOverlay extends StatelessWidget {
  /// Current detection state that controls the border color.
  final FaceAlignmentState state;

  /// Optional message displayed below the oval guide.
  final String? message;

  const FaceAlignmentOverlay({
    super.key,
    this.state = FaceAlignmentState.idle,
    this.message,
  });

  // ── Brand / state colors ──────────────────────────────────────────────────
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _green = Color(0xFF4CAF50);
  static const Color _amber = Color(0xFFFFC107);

  Color get _borderColor {
    switch (state) {
      case FaceAlignmentState.detected:
        return _green;
      case FaceAlignmentState.timeout:
        return _amber;
      case FaceAlignmentState.idle:
        return _white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // ── Oval guide border ───────────────────────────────────────────────
        CustomPaint(
          painter: _OvalGuidePainter(borderColor: _borderColor),
          child: const SizedBox.expand(),
        ),

        // ── Status message below the oval ───────────────────────────────────
        if (message != null)
          Positioned(
            bottom: 80,
            left: 24,
            right: 24,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          ),

        // ── Corner guide labels ─────────────────────────────────────────────
        Positioned(
          top: 40,
          child: Text(
            state == FaceAlignmentState.detected
                ? 'Face detected'
                : 'Position face within guide',
            style: TextStyle(
              color: _borderColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// The detection state that drives the overlay's visual appearance.
enum FaceAlignmentState {
  /// Camera is active but no face has been detected yet.
  idle,

  /// A face has been detected within the alignment guide.
  detected,

  /// The 10-second no-detection timeout has elapsed.
  timeout,
}

// ── Custom painter for the oval guide ────────────────────────────────────────

class _OvalGuidePainter extends CustomPainter {
  final Color borderColor;

  const _OvalGuidePainter({required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    // Semi-transparent dark overlay covering the area outside the oval.
    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    // The oval guide occupies roughly 70% of the width and 55% of the height,
    // centred slightly above the vertical midpoint.
    final double ovalWidth = size.width * 0.70;
    final double ovalHeight = size.height * 0.55;
    final double centerX = size.width / 2;
    final double centerY = size.height * 0.45;

    final ovalRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: ovalWidth,
      height: ovalHeight,
    );

    // Draw full overlay first, then cut out the oval using BlendMode.clear.
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), overlayPaint);
    canvas.drawOval(ovalRect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // Draw the oval border on top.
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(_OvalGuidePainter oldDelegate) =>
      oldDelegate.borderColor != borderColor;
}
