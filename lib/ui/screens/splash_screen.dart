import 'dart:async';

import 'package:flutter/material.dart';

/// NHAI Splash Screen
///
/// Displays for 2–3 seconds then navigates to `/home`.
/// Shows NHAI branding with government color palette:
///   - Deep Blue (#003580) background
///   - White (#FFFFFF) text
///   - Saffron (#FF6600) accent
///
/// If assets fail to load within 5 seconds, a fallback error screen is shown
/// with a retry option.
///
/// Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // ── Brand colors ──────────────────────────────────────────────────────────
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);

  // ── Timing constants ──────────────────────────────────────────────────────
  /// Minimum display duration before navigating (Requirement 1.1).
  static const Duration _minSplashDuration = Duration(seconds: 2);

  /// Maximum display duration before navigating (Requirement 1.1).
  static const Duration _maxSplashDuration = Duration(seconds: 3);

  /// Timeout for asset loading; triggers fallback error (Requirement 1.6).
  static const Duration _assetLoadTimeout = Duration(seconds: 5);

  // ── State ─────────────────────────────────────────────────────────────────
  bool _hasError = false;
  bool _assetsLoaded = false;

  late AnimationController _progressController;
  Timer? _navigationTimer;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();

    // Progress indicator animation runs for the max splash duration.
    _progressController = AnimationController(
      vsync: this,
      duration: _maxSplashDuration,
    )..forward();

    _startLoading();
  }

  /// Simulates asset loading and sets up navigation / timeout timers.
  void _startLoading() {
    setState(() {
      _hasError = false;
      _assetsLoaded = false;
    });

    // Timeout guard: if loading takes longer than 5 s, show error (Req 1.6).
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_assetLoadTimeout, () {
      if (!_assetsLoaded && mounted) {
        setState(() => _hasError = true);
        _navigationTimer?.cancel();
      }
    });

    // Simulate asset loading (fonts, images, etc.) — completes quickly in
    // practice; the minimum 2-second display is enforced by the navigation
    // timer below.
    _loadAssets().then((_) {
      if (!mounted) return;
      _timeoutTimer?.cancel();
      setState(() => _assetsLoaded = true);

      // Navigate after the minimum splash duration (Requirement 1.1).
      _navigationTimer?.cancel();
      _navigationTimer = Timer(_minSplashDuration, _navigateToHome);
    }).catchError((Object _) {
      if (!mounted) return;
      _timeoutTimer?.cancel();
      setState(() => _hasError = true);
    });
  }

  /// Loads any required assets. Throws on failure so the error path is taken.
  Future<void> _loadAssets() async {
    // In Phase 1 there are no binary asset files to load (the logo is
    // rendered as styled text). This future resolves immediately via a
    // microtask (no timer created, so tests stay clean).
    // Future phases can add image/font pre-caching here.
    await Future<void>.microtask(() {});
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  void dispose() {
    _progressController.dispose();
    _navigationTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deepBlue,
      body: _hasError ? _buildErrorView() : _buildSplashView(),
    );
  }

  // ── Splash view ───────────────────────────────────────────────────────────

  Widget _buildSplashView() {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),

            // NHAI logo placeholder — styled text in a decorative container
            // (Requirement 1.3: NHAI logo and name).
            _NhaiLogoBadge(),

            const SizedBox(height: 24),

            // NHAI name (Requirement 1.3)
            Text(
              'NHAI',
              style: TextStyle(
                color: _white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
              ),
            ),

            const SizedBox(height: 8),

            // Saffron divider accent (Requirement 1.4)
            Container(
              width: 60,
              height: 3,
              decoration: BoxDecoration(
                color: _saffron,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const SizedBox(height: 32),

            // Primary title (Requirement 1.2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Offline Workforce Authentication System',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Subtitle (Requirement 1.2)
            Text(
              'Powered by Edge AI',
              style: TextStyle(
                color: _saffron,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.2,
              ),
            ),

            const Spacer(flex: 2),

            // Minimal progress indicator (Requirement 1.5)
            _buildProgressIndicator(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return AnimatedBuilder(
      animation: _progressController,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: null, // indeterminate
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(_saffron),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Error / fallback view ─────────────────────────────────────────────────

  /// Fallback error screen shown when assets fail to load within 5 s
  /// (Requirement 1.6).
  Widget _buildErrorView() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                color: _saffron,
                size: 64,
              ),
              const SizedBox(height: 24),
              Text(
                'Failed to Load',
                style: TextStyle(
                  color: _white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'The application could not load its resources within the '
                'expected time. Please check the device storage and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _white.withValues(alpha: 0.8),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _saffron,
                  foregroundColor: _white,
                  minimumSize: const Size(160, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _retry() {
    _progressController
      ..reset()
      ..forward();
    _startLoading();
  }
}

// ── NHAI Logo Badge ───────────────────────────────────────────────────────────

/// Text-based NHAI logo placeholder.
///
/// Renders "NHAI" in a styled circular badge using the Saffron accent color.
/// Replace with an `Image.asset` widget once the official logo asset is added.
class _NhaiLogoBadge extends StatelessWidget {
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _saffron,
        border: Border.all(color: _white, width: 3),
        boxShadow: [
          BoxShadow(
            color: _saffron.withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Text(
          'NHAI',
          style: TextStyle(
            color: _deepBlue,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}
