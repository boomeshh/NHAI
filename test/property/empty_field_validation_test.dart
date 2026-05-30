// Feature: nhai-offline-auth, Property 5: Empty field validation rejects incomplete submissions
//
// **Validates: Requirements 3.2**
//
// Property: For any enrollment form submission where at least one of the three
// mandatory fields (Employee ID, Name, Department) is empty or composed
// entirely of whitespace, validateForm returns isValid=false and no record is
// written to storage.
//
// Minimum 100 iterations.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_impl.dart';

// ---------------------------------------------------------------------------
// Generator helpers
// ---------------------------------------------------------------------------

/// Whitespace characters used to build whitespace-only strings.
const _whitespaceChars = [' ', '\t', '\n', '\r', ' ', '\u00a0'];

/// Generates a random non-empty alphanumeric string of length [len].
String _randomAlphanumeric(Random rng, int len) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  return String.fromCharCodes(
    List.generate(len, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
  );
}

/// Generates a random non-empty printable string of length [len].
/// First and last characters are guaranteed non-whitespace.
String _randomPrintable(Random rng, int len) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-';
  if (len == 1) return 'A';
  final middle = len <= 2
      ? ''
      : String.fromCharCodes(
          List.generate(
              len - 2,
              (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
        );
  return 'A${middle}A';
}

/// Generates a random whitespace-only string of length 1–6.
String _randomWhitespaceOnly(Random rng) {
  final len = 1 + rng.nextInt(6); // 1..6
  return String.fromCharCodes(
    List.generate(
        len,
        (_) => _whitespaceChars[rng.nextInt(_whitespaceChars.length)]
            .codeUnitAt(0)),
  );
}

/// Returns either an empty string or a whitespace-only string — both are
/// "blank" values that must be rejected by validateForm.
String _randomBlankValue(Random rng) {
  return rng.nextBool() ? '' : _randomWhitespaceOnly(rng);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group(
      'Property 5: Empty field validation rejects incomplete submissions', () {
    late EnrollmentModuleImpl sut;

    setUp(() {
      sut = EnrollmentModuleImpl();
    });

    // -----------------------------------------------------------------------
    // Core property: any combination with at least one blank field is rejected.
    // We enumerate all 7 non-trivial subsets of {employeeId, name, department}
    // that contain at least one blank field, cycling through them across 100+
    // iterations so every combination is exercised.
    // -----------------------------------------------------------------------

    test(
        'property: at least one blank field always causes isValid=false '
        '(100 iterations, all blank-field combinations)', () {
      final rng = Random(42);

      // Valid base values used for the non-blank fields.
      String validId() =>
          _randomAlphanumeric(rng, 1 + rng.nextInt(20)); // 1..20
      String validName() => _randomPrintable(rng, 2 + rng.nextInt(59)); // 2..60
      String validDept() => _randomPrintable(rng, 2 + rng.nextInt(59)); // 2..60

      // 7 combinations where at least one field is blank:
      // 1: id blank, name valid, dept valid
      // 2: id valid, name blank, dept valid
      // 3: id valid, name valid, dept blank
      // 4: id blank, name blank, dept valid
      // 5: id blank, name valid, dept blank
      // 6: id valid, name blank, dept blank
      // 7: id blank, name blank, dept blank
      for (int i = 0; i < 100; i++) {
        final combo = (i % 7) + 1; // cycles 1..7

        final String employeeId;
        final String name;
        final String department;

        switch (combo) {
          case 1:
            employeeId = _randomBlankValue(rng);
            name = validName();
            department = validDept();
          case 2:
            employeeId = validId();
            name = _randomBlankValue(rng);
            department = validDept();
          case 3:
            employeeId = validId();
            name = validName();
            department = _randomBlankValue(rng);
          case 4:
            employeeId = _randomBlankValue(rng);
            name = _randomBlankValue(rng);
            department = validDept();
          case 5:
            employeeId = _randomBlankValue(rng);
            name = validName();
            department = _randomBlankValue(rng);
          case 6:
            employeeId = validId();
            name = _randomBlankValue(rng);
            department = _randomBlankValue(rng);
          default: // 7
            employeeId = _randomBlankValue(rng);
            name = _randomBlankValue(rng);
            department = _randomBlankValue(rng);
        }

        final result = sut.validateForm(employeeId, name, department);

        expect(
          result.isValid,
          isFalse,
          reason:
              'Iteration $i (combo $combo): validateForm must return isValid=false '
              'when at least one field is blank.\n'
              '  employeeId:  "${employeeId.replaceAll('\n', '\\n').replaceAll('\t', '\\t')}"\n'
              '  name:        "${name.replaceAll('\n', '\\n').replaceAll('\t', '\\t')}"\n'
              '  department:  "${department.replaceAll('\n', '\\n').replaceAll('\t', '\\t')}"',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Property: blank Employee ID alone is always rejected.
    // -----------------------------------------------------------------------

    test(
        'property: blank Employee ID (empty or whitespace-only) always causes '
        'isValid=false (100 iterations)', () {
      final rng = Random(7);

      for (int i = 0; i < 100; i++) {
        final employeeId = _randomBlankValue(rng);
        final name = _randomPrintable(rng, 2 + rng.nextInt(59));
        final department = _randomPrintable(rng, 2 + rng.nextInt(59));

        final result = sut.validateForm(employeeId, name, department);

        expect(
          result.isValid,
          isFalse,
          reason:
              'Iteration $i: blank Employee ID must be rejected.\n'
              '  employeeId: "${employeeId.replaceAll('\n', '\\n').replaceAll('\t', '\\t')}"',
        );

        expect(
          result.fieldErrors.containsKey('employeeId'),
          isTrue,
          reason:
              'Iteration $i: fieldErrors must contain an error for "employeeId".',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Property: blank Name alone is always rejected.
    // -----------------------------------------------------------------------

    test(
        'property: blank Name (empty or whitespace-only) always causes '
        'isValid=false (100 iterations)', () {
      final rng = Random(13);

      for (int i = 0; i < 100; i++) {
        final employeeId = _randomAlphanumeric(rng, 1 + rng.nextInt(20));
        final name = _randomBlankValue(rng);
        final department = _randomPrintable(rng, 2 + rng.nextInt(59));

        final result = sut.validateForm(employeeId, name, department);

        expect(
          result.isValid,
          isFalse,
          reason:
              'Iteration $i: blank Name must be rejected.\n'
              '  name: "${name.replaceAll('\n', '\\n').replaceAll('\t', '\\t')}"',
        );

        expect(
          result.fieldErrors.containsKey('name'),
          isTrue,
          reason:
              'Iteration $i: fieldErrors must contain an error for "name".',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Property: blank Department alone is always rejected.
    // -----------------------------------------------------------------------

    test(
        'property: blank Department (empty or whitespace-only) always causes '
        'isValid=false (100 iterations)', () {
      final rng = Random(99);

      for (int i = 0; i < 100; i++) {
        final employeeId = _randomAlphanumeric(rng, 1 + rng.nextInt(20));
        final name = _randomPrintable(rng, 2 + rng.nextInt(59));
        final department = _randomBlankValue(rng);

        final result = sut.validateForm(employeeId, name, department);

        expect(
          result.isValid,
          isFalse,
          reason:
              'Iteration $i: blank Department must be rejected.\n'
              '  department: "${department.replaceAll('\n', '\\n').replaceAll('\t', '\\t')}"',
        );

        expect(
          result.fieldErrors.containsKey('department'),
          isTrue,
          reason:
              'Iteration $i: fieldErrors must contain an error for "department".',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Property: all three fields blank is rejected with errors for all fields.
    // -----------------------------------------------------------------------

    test(
        'property: all three fields blank causes isValid=false with errors '
        'for all three fields (100 iterations)', () {
      final rng = Random(55);

      for (int i = 0; i < 100; i++) {
        final employeeId = _randomBlankValue(rng);
        final name = _randomBlankValue(rng);
        final department = _randomBlankValue(rng);

        final result = sut.validateForm(employeeId, name, department);

        expect(
          result.isValid,
          isFalse,
          reason: 'Iteration $i: all-blank submission must be rejected.',
        );

        expect(
          result.fieldErrors.containsKey('employeeId'),
          isTrue,
          reason:
              'Iteration $i: fieldErrors must contain an error for "employeeId".',
        );
        expect(
          result.fieldErrors.containsKey('name'),
          isTrue,
          reason:
              'Iteration $i: fieldErrors must contain an error for "name".',
        );
        expect(
          result.fieldErrors.containsKey('department'),
          isTrue,
          reason:
              'Iteration $i: fieldErrors must contain an error for "department".',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Specific whitespace variants: spaces, tabs, newlines, mixed.
    // -----------------------------------------------------------------------

    test('empty string Employee ID is rejected', () {
      final result = sut.validateForm('', 'Alice Kumar', 'Engineering');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.containsKey('employeeId'), isTrue);
    });

    test('spaces-only Employee ID is rejected', () {
      final result = sut.validateForm('   ', 'Alice Kumar', 'Engineering');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.containsKey('employeeId'), isTrue);
    });

    test('tab-only Employee ID is rejected', () {
      final result = sut.validateForm('\t\t', 'Alice Kumar', 'Engineering');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.containsKey('employeeId'), isTrue);
    });

    test('newline-only Employee ID is rejected', () {
      final result = sut.validateForm('\n', 'Alice Kumar', 'Engineering');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.containsKey('employeeId'), isTrue);
    });

    test('empty string Name is rejected', () {
      final result = sut.validateForm('EMP001', '', 'Engineering');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.containsKey('name'), isTrue);
    });

    test('spaces-only Name is rejected', () {
      final result = sut.validateForm('EMP001', '   ', 'Engineering');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.containsKey('name'), isTrue);
    });

    test('tab-only Name is rejected', () {
      final result = sut.validateForm('EMP001', '\t', 'Engineering');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.containsKey('name'), isTrue);
    });

    test('empty string Department is rejected', () {
      final result = sut.validateForm('EMP001', 'Alice Kumar', '');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.containsKey('department'), isTrue);
    });

    test('spaces-only Department is rejected', () {
      final result = sut.validateForm('EMP001', 'Alice Kumar', '   ');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.containsKey('department'), isTrue);
    });

    test('mixed whitespace Department is rejected', () {
      final result = sut.validateForm('EMP001', 'Alice Kumar', ' \t\n ');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.containsKey('department'), isTrue);
    });

    test('all three fields empty strings are rejected', () {
      final result = sut.validateForm('', '', '');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.containsKey('employeeId'), isTrue);
      expect(result.fieldErrors.containsKey('name'), isTrue);
      expect(result.fieldErrors.containsKey('department'), isTrue);
    });

    test('all three fields whitespace-only are rejected', () {
      final result = sut.validateForm(' \t ', '\n\n', '\r\n');
      expect(result.isValid, isFalse);
      expect(result.fieldErrors.containsKey('employeeId'), isTrue);
      expect(result.fieldErrors.containsKey('name'), isTrue);
      expect(result.fieldErrors.containsKey('department'), isTrue);
    });

    // -----------------------------------------------------------------------
    // Contrast: valid inputs are accepted (sanity check).
    // -----------------------------------------------------------------------

    test('valid non-blank inputs are accepted', () {
      final result =
          sut.validateForm('EMP001', 'Alice Kumar', 'Engineering');
      expect(result.isValid, isTrue);
      expect(result.fieldErrors, isEmpty);
    });
  });
}
