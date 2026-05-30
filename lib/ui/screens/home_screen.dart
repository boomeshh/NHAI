import 'package:flutter/material.dart';

import '../widgets/status_badge.dart';

/// NHAI Home Screen
///
/// Displays the two primary action buttons ("Enroll Employee" and
/// "Authenticate Employee"), an always-visible "Offline Mode Active"
/// [StatusBadge], and a navigation entry to the Local Logs screen.
///
/// Color palette (matches SplashScreen):
///   - Deep Blue (#003580) — primary background / app bar
///   - White (#FFFFFF)     — text and icons
///   - Saffron (#FF6600)   — accent elements
///
/// All interactive elements meet the minimum 48×48 dp touch target
/// requirement (Requirement 2.2).
///
/// Requirements: 2.1, 2.2, 2.3, 2.4, 2.5
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // ── Brand colors ──────────────────────────────────────────────────────────
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deepBlue,
      appBar: AppBar(
        backgroundColor: _deepBlue,
        elevation: 0,
        title: const Text(
          'NHAI Authentication',
          style: TextStyle(
            color: _white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        // "View Logs" action in the app bar (Requirement 2.4)
        actions: [
          Tooltip(
            message: 'View Logs',
            child: IconButton(
              key: const Key('view_logs_icon_button'),
              icon: const Icon(Icons.history, color: _white),
              iconSize: 28,
              // Ensure the tap area meets the 48×48 dp minimum (Req 2.2).
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => Navigator.of(context).pushNamed('/logs'),
              tooltip: 'View Logs',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Offline status badge (Requirement 2.3) ──────────────────
              Center(
                child: const StatusBadge(),
              ),

              const SizedBox(height: 48),

              // ── NHAI logo / title area ────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _saffron,
                        border: Border.all(color: _white, width: 2.5),
                      ),
                      child: const Center(
                        child: Text(
                          'NHAI',
                          style: TextStyle(
                            color: _deepBlue,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Offline Workforce Authentication',
                      style: TextStyle(
                        color: _white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // ── Primary action buttons (Requirements 2.1, 2.2) ───────────

              // "Enroll Employee" button — navigates to /enroll
              _PrimaryActionButton(
                key: const Key('enroll_employee_button'),
                label: 'Enroll Employee',
                icon: Icons.person_add_alt_1,
                onPressed: () => Navigator.of(context).pushNamed('/enroll'),
              ),

              const SizedBox(height: 20),

              // "Authenticate Employee" button — navigates to /authenticate
              _PrimaryActionButton(
                key: const Key('authenticate_employee_button'),
                label: 'Authenticate Employee',
                icon: Icons.verified_user,
                onPressed: () =>
                    Navigator.of(context).pushNamed('/authenticate'),
              ),

              const Spacer(),

              // ── Navigation entry to Local Logs (Requirement 2.4) ─────────
              _ViewLogsButton(
                key: const Key('view_logs_button'),
                onPressed: () => Navigator.of(context).pushNamed('/logs'),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Primary Action Button ─────────────────────────────────────────────────────

/// A large, accessible action button styled with the NHAI color palette.
///
/// The button always meets the 48×48 dp minimum touch target (Requirement 2.2).
class _PrimaryActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);

  const _PrimaryActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _saffron,
          foregroundColor: _white,
          // Minimum 48 dp height satisfies Requirement 2.2.
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 3,
          shadowColor: _saffron.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

// ── View Logs Button ──────────────────────────────────────────────────────────

/// An outlined button that navigates to the Local Logs screen.
///
/// Styled as a secondary action to visually distinguish it from the primary
/// enrollment / authentication buttons (Requirement 2.4).
class _ViewLogsButton extends StatelessWidget {
  final VoidCallback onPressed;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);

  const _ViewLogsButton({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'View Logs',
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.list_alt, size: 20),
        label: const Text(
          'View Logs',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _white,
          side: const BorderSide(color: _saffron, width: 1.5),
          // Minimum 48 dp height satisfies Requirement 2.2.
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
