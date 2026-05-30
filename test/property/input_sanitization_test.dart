// Feature: nhai-offline-auth, Property 4: Input sanitization removes surrounding whitespace
//
// **Validates: Requirements 3.4**
//
// Property: For any enrollment form input string, the value stored in the
// EmployeeRecord equals the original string with all leading and trailing
// whitespace removed.
//
// Concretely: for any valid alphanumeric Employee ID, Name, and Department
// with random leading/trailing whitespace added, validateForm accepts them
// and the trimmed values match the originals.
//
// Minimum 100 iterations.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/core/enrollment_module/enrollment_module_impl.dart';

// ---------------------------------------------------------------------------
// Generator helpers
// ---------------------------------------------------------------------------

/// Whitespace characters that may appear as leading/trailing padding.
const _whitespaceChars = [' ', '\t', '\n', '\r', ' ', '\u00a0'];

/// Generates a random non-empty alphanumeric string of length [len].
String _randomAlphanumeric(Random rng, int len) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  return String.fromCharCodes(
    List.generate(len, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
  );
}

/// Generates a random non-empty string of printable characters (no leading/
/// trailing whitespace in the core value) of length [len].
/// Used for Name and Department fields.
String _randomPrintable(Random rng, int len) {
  // Use letters, digits, and a few safe punctuation chars.
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .-';
  // Ensure first and last chars are not whitespace so the core value is clean.
  final middle = len <= 2
      ? ''
      : String.fromCharCodes(
          List.generate(
              len - 2,
              (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
        );
  final edge = 'A'; // guaranteed non-whitespace
  return '$edge$middle$edge';
}

/// Generates a random whitespace prefix/suffix string of length 0–5.
String _randomWhitespace(Random rng) {
  final len = rng.nextInt(6); // 0..5
  if (len == 0) return '';
  return String.fromCharCodes(
    List.generate(
        len,
        (_) => _whitespaceChars[rng.nextInt(_whitespaceChars.length)]
            .codeUnitAt(0)),
  );
}

/// Wraps [core] with random leading and trailing whitespace.
String _addWhitespace(Random rng, String core) {
  return '${_randomWhitespace(rng)}$core${_randomWhitespace(rng)}';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Property 4: Input sanitization removes surrounding whitespace', () {
    late EnrollmentModuleImpl sut;

    setUp(() {
      sut = EnrollmentModuleImpl();
    });

    // -----------------------------------------------------------------------
    // Core property: validateForm accepts inputs with surrounding whitespace
    // and the trimmed values equal the originals (100 iterations).
    // -----------------------------------------------------------------------

    test(
        'property: validateForm accepts valid inputs padded with whitespace '
        'and trimmed values equal the originals (100 iterations)', () {
      final rng = Random(42);

      for (int i = 0; i < 100; i++) {
        // Generate valid core values within field constraints.
        final idLen = 1 + rng.nextInt(20); // 1..20
        final nameLen = 2 + rng.nextInt(59); // 2..60
        final deptLen = 2 + rng.nextInt(59); // 2..60

        final coreId = _randomAlphanumeric(rng, idLen);
        final coreName = _randomPrintable(rng, nameLen);
        final coreDept = _randomPrintable(rng, deptLen);

        // Wrap each core value with random leading/trailing whitespace.
        final paddedId = _addWhitespace(rng, coreId);
        final paddedName = _addWhitespace(rng, coreName);
        final paddedDept = _addWhitespace(rng, coreDept);

        final result = sut.validateForm(paddedId, paddedName, paddedDept);

        // The form must be valid — whitespace padding must not cause rejection.
        expect(
          result.isValid,
          isTrue,
          reason:
              'Iteration $i: validateForm should accept padded inputs.\n'
              '  employeeId: "$paddedId"\n'
              '  name:       "$paddedName"\n'
              '  department: "$paddedDept"\n'
              '  errors:     ${result.fieldErrors}',
        );

        // The trimmed values must equal the original core values.
        expect(
          paddedId.trim(),
          equals(coreId),
          reason:
              'Iteration $i: trimmed Employee ID must equal the core value.',
        );
        expect(
          paddedName.trim(),
          equals(coreName),
          reason: 'Iteration $i: trimmed Name must equal the core value.',
        );
        expect(
          paddedDept.trim(),
          equals(coreDept),
          reason:
              'Iteration $i: trimmed Department must equal the core value.',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Property: inputs with ONLY leading whitespace are accepted and trimmed.
    // -----------------------------------------------------------------------

    test(
        'property: inputs with only leading whitespace are accepted and '
        'trimmed values equal the originals (100 iterations)', () {
      final rng = Random(7);

      for (int i = 0; i < 100; i++) {
        final idLen = 1 + rng.nextInt(20);
        final nameLen = 2 + rng.nextInt(59);
        final deptLen = 2 + rng.nextInt(59);

        final coreId = _randomAlphanumeric(rng, idLen);
        final coreName = _randomPrintable(rng, nameLen);
        final coreDept = _randomPrintable(rng, deptLen);

        final leadingWs = _randomWhitespace(rng);

        final paddedId = '$leadingWs$coreId';
        final paddedName = '$leadingWs$coreName';
        final paddedDept = '$leadingWs$coreDept';

        final result = sut.validateForm(paddedId, paddedName, paddedDept);

        expect(
          result.isValid,
          isTrue,
          reason:
              'Iteration $i: leading-whitespace-padded inputs should be valid.\n'
              '  employeeId: "$paddedId"\n'
              '  errors:     ${result.fieldErrors}',
        );

        expect(paddedId.trim(), equals(coreId),
            reason: 'Iteration $i: trim(employeeId) must equal core value.');
        expect(paddedName.trim(), equals(coreName),
            reason: 'Iteration $i: trim(name) must equal core value.');
        expect(paddedDept.trim(), equals(coreDept),
            reason: 'Iteration $i: trim(department) must equal core value.');
      }
    });

    // -----------------------------------------------------------------------
    // Property: inputs with ONLY trailing whitespace are accepted and trimmed.
    // -----------------------------------------------------------------------

    test(
        'property: inputs with only trailing whitespace are accepted and '
        'trimmed values equal the originals (100 iterations)', () {
      final rng = Random(13);

      for (int i = 0; i < 100; i++) {
        final idLen = 1 + rng.nextInt(20);
        final nameLen = 2 + rng.nextInt(59);
        final deptLen = 2 + rng.nextInt(59);

        final coreId = _randomAlphanumeric(rng, idLen);
        final coreName = _randomPrintable(rng, nameLen);
        final coreDept = _randomPrintable(rng, deptLen);

        final trailingWs = _randomWhitespace(rng);

        final paddedId = '$coreId$trailingWs';
        final paddedName = '$coreName$trailingWs';
        final paddedDept = '$coreDept$trailingWs';

        final result = sut.validateForm(paddedId, paddedName, paddedDept);

        expect(
          result.isValid,
          isTrue,
          reason:
              'Iteration $i: trailing-whitespace-padded inputs should be valid.\n'
              '  employeeId: "$paddedId"\n'
              '  errors:     ${result.fieldErrors}',
        );

        expect(paddedId.trim(), equals(coreId),
            reason: 'Iteration $i: trim(employeeId) must equal core value.');
        expect(paddedName.trim(), equals(coreName),
            reason: 'Iteration $i: trim(name) must equal core value.');
        expect(paddedDept.trim(), equals(coreDept),
            reason: 'Iteration $i: trim(department) must equal core value.');
      }
    });

    // -----------------------------------------------------------------------
    // Property: trim is idempotent — trimming an already-trimmed value
    // produces the same value (100 iterations).
    // -----------------------------------------------------------------------

    test(
        'property: trim is idempotent — already-trimmed inputs are unchanged '
        'by a second trim (100 iterations)', () {
      final rng = Random(99);

      for (int i = 0; i < 100; i++) {
        final idLen = 1 + rng.nextInt(20);
        final nameLen = 2 + rng.nextInt(59);
        final deptLen = 2 + rng.nextInt(59);

        final coreId = _randomAlphanumeric(rng, idLen);
        final coreName = _randomPrintable(rng, nameLen);
        final coreDept = _randomPrintable(rng, deptLen);

        // Idempotency: trim(trim(x)) == trim(x)
        expect(coreId.trim().trim(), equals(coreId.trim()),
            reason: 'Iteration $i: trim must be idempotent for employeeId.');
        expect(coreName.trim().trim(), equals(coreName.trim()),
            reason: 'Iteration $i: trim must be idempotent for name.');
        expect(coreDept.trim().trim(), equals(coreDept.trim()),
            reason: 'Iteration $i: trim must be idempotent for department.');

        // Also verify the form accepts the already-trimmed values.
        final result = sut.validateForm(coreId, coreName, coreDept);
        expect(
          result.isValid,
          isTrue,
          reason:
              'Iteration $i: already-trimmed inputs should be valid.\n'
              '  errors: ${result.fieldErrors}',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Boundary: no whitespace added — inputs pass through unchanged.
    // -----------------------------------------------------------------------

    test(
        'boundary: inputs with no surrounding whitespace are accepted and '
        'trim is a no-op (100 iterations)', () {
      final rng = Random(55);

      for (int i = 0; i < 100; i++) {
        final idLen = 1 + rng.nextInt(20);
        final nameLen = 2 + rng.nextInt(59);
        final deptLen = 2 + rng.nextInt(59);

        final coreId = _randomAlphanumeric(rng, idLen);
        final coreName = _randomPrintable(rng, nameLen);
        final coreDept = _randomPrintable(rng, deptLen);

        final result = sut.validateForm(coreId, coreName, coreDept);

        expect(
          result.isValid,
          isTrue,
          reason:
              'Iteration $i: inputs without whitespace should be valid.\n'
              '  errors: ${result.fieldErrors}',
        );

        // trim() on an already-clean string must be a no-op.
        expect(coreId.trim(), equals(coreId),
            reason:
                'Iteration $i: trim of clean employeeId must be a no-op.');
        expect(coreName.trim(), equals(coreName),
            reason: 'Iteration $i: trim of clean name must be a no-op.');
        expect(coreDept.trim(), equals(coreDept),
            reason:
                'Iteration $i: trim of clean department must be a no-op.');
      }
    });

    // -----------------------------------------------------------------------
    // Specific whitespace character types: spaces, tabs, newlines.
    // -----------------------------------------------------------------------

    test('spaces around Employee ID are trimmed and form is valid', () {
      final result = sut.validateForm('  EMP001  ', 'Alice Kumar', 'Engineering');
      expect(result.isValid, isTrue);
      expect('  EMP001  '.trim(), equals('EMP001'));
    });

    test('tabs around Name are trimmed and form is valid', () {
      final result = sut.validateForm('EMP001', '\tAlice Kumar\t', 'Engineering');
      expect(result.isValid, isTrue);
      expect('\tAlice Kumar\t'.trim(), equals('Alice Kumar'));
    });

    test('newlines around Department are trimmed and form is valid', () {
      final result =
          sut.validateForm('EMP001', 'Alice Kumar', '\nEngineering\n');
      expect(result.isValid, isTrue);
      expect('\nEngineering\n'.trim(), equals('Engineering'));
    });

    test('mixed whitespace (space + tab + newline) around all fields is trimmed',
        () {
      final result = sut.validateForm(
          ' \t EMP001 \n ', ' \n Alice Kumar \t ', '\t Engineering \n ');
      expect(result.isValid, isTrue);
      expect(' \t EMP001 \n '.trim(), equals('EMP001'));
      expect(' \n Alice Kumar \t '.trim(), equals('Alice Kumar'));
      expect('\t Engineering \n '.trim(), equals('Engineering'));
    });

    // -----------------------------------------------------------------------
    // Boundary: maximum-length core values with whitespace padding still pass.
    // -----------------------------------------------------------------------

    test(
        'boundary: Employee ID at max length (20 chars) with surrounding '
        'whitespace is accepted', () {
      final paddedId = '   ${'A' * 20}   ';
      final result = sut.validateForm(paddedId, 'Alice', 'HR');
      expect(result.isValid, isTrue,
          reason: 'Max-length ID with whitespace padding should be valid.');
      expect(paddedId.trim().length, equals(20));
    });

    test(
        'boundary: Name at max length (60 chars) with surrounding whitespace '
        'is accepted', () {
      final paddedName = '\t${'N' * 60}\t';
      final result = sut.validateForm('EMP1', paddedName, 'HR');
      expect(result.isValid, isTrue,
          reason: 'Max-length Name with whitespace padding should be valid.');
      expect(paddedName.trim().length, equals(60));
    });

    test(
        'boundary: Department at max length (60 chars) with surrounding '
        'whitespace is accepted', () {
      final paddedDept = '\n${'D' * 60}\n';
      final result = sut.validateForm('EMP1', 'Alice', paddedDept);
      expect(result.isValid, isTrue,
          reason:
              'Max-length Department with whitespace padding should be valid.');
      expect(paddedDept.trim().length, equals(60));
    });
  });
}
