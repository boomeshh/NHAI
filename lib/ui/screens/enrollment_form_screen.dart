import 'package:flutter/material.dart';

import '../../core/enrollment_module/enrollment_module_interface.dart';
import '../../core/storage_manager/storage_manager_interface.dart';

/// NHAI Enrollment Form Screen
///
/// Presents a form with three mandatory fields:
///   - Employee ID (alphanumeric, max 20 characters)
///   - Name (text, max 60 characters)
///   - Department (text, max 60 characters)
///
/// On submit:
///   1. Calls [EnrollmentModuleInterface.validateForm] and displays
///      field-level errors inline when validation fails.
///   2. Checks for a duplicate Employee ID via
///      [StorageManagerInterface.employeeExists]; if a duplicate is found,
///      shows an [AlertDialog] with "Overwrite" and "Cancel" options.
///   3. On a valid, non-duplicate submission, navigates to `/face-capture`.
///
/// Color palette (matches SplashScreen / HomeScreen):
///   - Deep Blue (#003580) — primary background / app bar
///   - White (#FFFFFF)     — text and icons
///   - Saffron (#FF6600)   — accent elements
///
/// The screen accepts its dependencies via constructor injection to remain
/// fully testable without a running Flutter app.
///
/// Requirements: 3.1, 3.2, 3.3
class EnrollmentFormScreen extends StatefulWidget {
  /// The enrollment module used for form validation.
  final EnrollmentModuleInterface enrollmentModule;

  /// The storage manager used to check for duplicate Employee IDs.
  final StorageManagerInterface storageManager;

  const EnrollmentFormScreen({
    super.key,
    required this.enrollmentModule,
    required this.storageManager,
  });

  @override
  State<EnrollmentFormScreen> createState() => _EnrollmentFormScreenState();
}

class _EnrollmentFormScreenState extends State<EnrollmentFormScreen> {
  // ── Brand colors ──────────────────────────────────────────────────────────
  static const Color _deepBlue = Color(0xFF003580);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _errorRed = Color(0xFFD32F2F);

  // ── Form state ────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();

  final _employeeIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _departmentController = TextEditingController();

  /// Field-level error messages returned by [EnrollmentModuleInterface.validateForm].
  String? _employeeIdError;
  String? _nameError;
  String? _departmentError;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _employeeIdController.dispose();
    _nameController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  // ── Submit logic ──────────────────────────────────────────────────────────

  Future<void> _onSubmit() async {
    // Clear previous errors.
    setState(() {
      _employeeIdError = null;
      _nameError = null;
      _departmentError = null;
    });

    final employeeId = _employeeIdController.text;
    final name = _nameController.text;
    final department = _departmentController.text;

    // 1. Validate via EnrollmentModule (Requirement 3.1, 3.2).
    final result = widget.enrollmentModule.validateForm(
      employeeId,
      name,
      department,
    );

    if (!result.isValid) {
      setState(() {
        _employeeIdError = result.fieldErrors['employeeId'];
        _nameError = result.fieldErrors['name'];
        _departmentError = result.fieldErrors['department'];
      });
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 2. Check for duplicate Employee ID (Requirement 3.3).
      final trimmedId = employeeId.trim();
      final isDuplicate = await widget.storageManager.employeeExists(trimmedId);

      if (!mounted) return;

      bool allowOverwrite = false;
      if (isDuplicate) {
        final shouldOverwrite = await _showDuplicateDialog(trimmedId);
        if (!mounted) return;
        if (shouldOverwrite != true) {
          // Operator chose "Cancel" — stay on the form.
          setState(() => _isSubmitting = false);
          return;
        }
        allowOverwrite = true;
        // Operator chose "Overwrite" — proceed to face capture.
      }

      // 3. Navigate to face capture (Requirement 3.3).
      if (mounted) {
        Navigator.of(context).pushNamed(
          '/face-capture',
          arguments: EmployeeFormData(
            employeeId: trimmedId,
            name: name.trim(),
            department: department.trim(),
            allowOverwrite: allowOverwrite,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'An error occurred: ${e.toString()}',
              style: const TextStyle(color: _white),
            ),
            backgroundColor: _errorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Shows a duplicate-record warning dialog.
  ///
  /// Returns `true` if the operator chose "Overwrite", `false` / `null`
  /// if they chose "Cancel" or dismissed the dialog.
  Future<bool?> _showDuplicateDialog(String employeeId) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _deepBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _saffron, width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: _saffron, size: 28),
            SizedBox(width: 10),
            Text(
              'Duplicate Record',
              style: TextStyle(
                color: _white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'An employee with ID "$employeeId" already exists in the system.\n\n'
          'Do you want to overwrite the existing record?',
          style: const TextStyle(
            color: _white,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          // "Cancel" — keep existing record, stay on form.
          TextButton(
            key: const Key('duplicate_dialog_cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: _white,
              minimumSize: const Size(80, 44),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          // "Overwrite" — proceed with enrollment, replacing existing record.
          ElevatedButton(
            key: const Key('duplicate_dialog_overwrite'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _saffron,
              foregroundColor: _white,
              minimumSize: const Size(100, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Overwrite',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deepBlue,
      appBar: AppBar(
        backgroundColor: _deepBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
        title: const Text(
          'Enroll Employee',
          style: TextStyle(
            color: _white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        // Saffron bottom border accent.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(color: _saffron, height: 2),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Section header ──────────────────────────────────────────
                const Text(
                  'Employee Details',
                  style: TextStyle(
                    color: _saffron,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Container(height: 1, color: _saffron.withValues(alpha: 0.3)),
                const SizedBox(height: 24),

                // ── Employee ID field ───────────────────────────────────────
                _FormField(
                  key: const Key('employee_id_field'),
                  controller: _employeeIdController,
                  label: 'Employee ID',
                  hint: 'Alphanumeric, max 20 characters',
                  errorText: _employeeIdError,
                  maxLength: 20,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.text,
                ),

                const SizedBox(height: 20),

                // ── Name field ──────────────────────────────────────────────
                _FormField(
                  key: const Key('name_field'),
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'Max 60 characters',
                  errorText: _nameError,
                  maxLength: 60,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.name,
                ),

                const SizedBox(height: 20),

                // ── Department field ────────────────────────────────────────
                _FormField(
                  key: const Key('department_field'),
                  controller: _departmentController,
                  label: 'Department',
                  hint: 'Max 60 characters',
                  errorText: _departmentError,
                  maxLength: 60,
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.text,
                  onFieldSubmitted: (_) => _isSubmitting ? null : _onSubmit(),
                ),

                const SizedBox(height: 40),

                // ── Submit button ───────────────────────────────────────────
                Semantics(
                  button: true,
                  label: 'Submit enrollment form',
                  child: ElevatedButton(
                    key: const Key('submit_button'),
                    onPressed: _isSubmitting ? null : _onSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _saffron,
                      foregroundColor: _white,
                      disabledBackgroundColor: _saffron.withValues(alpha: 0.5),
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                      shadowColor: _saffron.withValues(alpha: 0.4),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(_white),
                            ),
                          )
                        : const Text(
                            'Continue to Face Capture',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Hint text ───────────────────────────────────────────────
                Text(
                  'All fields are mandatory. Employee ID must be alphanumeric.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _white.withValues(alpha: 0.55),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Reusable form field widget ────────────────────────────────────────────────

/// A styled text field that matches the NHAI Deep Blue / White / Saffron
/// color palette and displays an inline error message below the input.
class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final String? errorText;
  final int maxLength;
  final TextInputAction textInputAction;
  final TextInputType keyboardType;
  final ValueChanged<String>? onFieldSubmitted;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _saffron = Color(0xFFFF6600);
  static const Color _errorRed = Color(0xFFEF9A9A);

  const _FormField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.errorText,
    required this.maxLength,
    required this.textInputAction,
    required this.keyboardType,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Text(
          label,
          style: TextStyle(
            color: hasError ? _errorRed : _white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),

        // Text input
        TextField(
          controller: controller,
          maxLength: maxLength,
          textInputAction: textInputAction,
          keyboardType: keyboardType,
          onSubmitted: onFieldSubmitted,
          style: const TextStyle(
            color: _white,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: _white.withValues(alpha: 0.4),
              fontSize: 13,
            ),
            counterStyle: TextStyle(
              color: _white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
            filled: true,
            fillColor: _white.withValues(alpha: 0.08),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: hasError ? _errorRed : _white.withValues(alpha: 0.25),
                width: hasError ? 1.5 : 1.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: hasError ? _errorRed : _saffron,
                width: 1.8,
              ),
            ),
          ),
        ),

        // Inline error message (Requirement 3.2)
        if (hasError) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.error_outline, color: _errorRed, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  errorText!,
                  style: const TextStyle(
                    color: _errorRed,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
