import 'package:flutter/material.dart';

/// A badge widget that displays the current connectivity / mode status.
///
/// For Phase 1 MVP the app is fully offline-only, so this badge always
/// shows "Offline Mode Active" with the appropriate styling.
///
/// Color palette:
///   - Deep Blue (#003580) background
///   - White (#FFFFFF) text
///   - Saffron (#FF6600) accent / icon
///
/// Requirements: 2.3, 2.5, 11.2, 11.3
class StatusBadge extends StatelessWidget {
  /// The label text shown inside the badge.
  ///
  /// Defaults to "Offline Mode Active" for Phase 1 MVP.
  final String label;

  /// Icon displayed to the left of the label.
  ///
  /// Defaults to [Icons.wifi_off] to signal offline status.
  final IconData icon;

  const StatusBadge({
    super.key,
    this.label = 'Offline Mode Active',
    this.icon = Icons.wifi_off,
  });

  // ── Brand colors ──────────────────────────────────────────────────────────
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _deepBlue = Color(0xFF003580);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _deepBlue,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _saffron, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _saffron, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: _white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
