import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/features/auth/presentation/auth_validators.dart';

void main() {
  group('AuthValidators.required', () {
    test('rejects empty and whitespace-only values', () {
      expect(AuthValidators.required(''), isNotNull);
      expect(AuthValidators.required('   '), isNotNull);
      expect(AuthValidators.required(null), isNotNull);
    });

    test('accepts a non-empty value', () {
      expect(AuthValidators.required('alice'), isNull);
    });
  });

  group('AuthValidators.username', () {
    test('rejects too short', () => expect(AuthValidators.username('ab'), isNotNull));
    test('rejects too long', () => expect(AuthValidators.username('a' * 31), isNotNull));
    test(
      'rejects invalid characters',
      () => expect(AuthValidators.username('alice smith!'), isNotNull),
    );
    test('accepts a valid username', () => expect(AuthValidators.username('alice_01'), isNull));
    test(
      'accepts dots and hyphens',
      () => expect(AuthValidators.username('alice.b-01'), isNull),
    );
  });

  group('AuthValidators.email', () {
    test('rejects missing @', () => expect(AuthValidators.email('not-an-email'), isNotNull));
    test('rejects missing domain', () => expect(AuthValidators.email('alice@'), isNotNull));
    test('accepts a valid email', () => expect(AuthValidators.email('alice@example.com'), isNull));
  });

  group('AuthValidators.password', () {
    test('rejects short passwords', () => expect(AuthValidators.password('Ab1!'), isNotNull));
    test(
      'rejects missing uppercase',
      () => expect(AuthValidators.password('str0ng!pass'), isNotNull),
    );
    test(
      'rejects missing lowercase',
      () => expect(AuthValidators.password('STR0NG!PASS'), isNotNull),
    );
    test('rejects missing digit', () => expect(AuthValidators.password('Strong!Pass'), isNotNull));
    test(
      'rejects missing special character',
      () => expect(AuthValidators.password('Str0ngPass'), isNotNull),
    );
    test('accepts a strong password', () => expect(AuthValidators.password('Str0ng!Pass'), isNull));
  });

  group('AuthValidators.passwordRequirementIssues', () {
    test('lists every unmet requirement for an empty password', () {
      expect(AuthValidators.passwordRequirementIssues(''), hasLength(5));
    });

    test('lists no issues for a fully compliant password', () {
      expect(AuthValidators.passwordRequirementIssues('Str0ng!Pass'), isEmpty);
    });
  });

  group('AuthValidators.confirmPassword', () {
    test('rejects a mismatch', () {
      final validator = AuthValidators.confirmPassword(() => 'Str0ng!Pass');
      expect(validator('Different1!'), isNotNull);
    });

    test('accepts a match', () {
      final validator = AuthValidators.confirmPassword(() => 'Str0ng!Pass');
      expect(validator('Str0ng!Pass'), isNull);
    });
  });
}
