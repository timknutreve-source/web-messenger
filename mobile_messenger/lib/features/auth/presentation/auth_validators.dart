/// Client-side form validation, mirroring the backend's rules so users get
/// instant feedback. The backend re-validates everything server-side
/// regardless - these checks are a UX convenience only, not a security boundary.
class AuthValidators {
  const AuthValidators._();

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _usernamePattern = RegExp(r'^[a-zA-Z0-9_.-]+$');
  static final _lowercase = RegExp(r'[a-z]');
  static final _uppercase = RegExp(r'[A-Z]');
  static final _digit = RegExp(r'\d');
  static final _specialChar = RegExp(r'[^a-zA-Z0-9]');

  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? username(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Username is required';
    if (trimmed.length < 3 || trimmed.length > 30) {
      return 'Username must be between 3 and 30 characters';
    }
    if (!_usernamePattern.hasMatch(trimmed)) {
      return "Username may only contain letters, digits, '.', '_' and '-'";
    }
    return null;
  }

  static String? email(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email is required';
    if (!_emailPattern.hasMatch(trimmed)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// Returns each unmet password requirement, in display order.
  static List<String> passwordRequirementIssues(String value) {
    final issues = <String>[];
    if (value.length < 8) issues.add('At least 8 characters');
    if (!_lowercase.hasMatch(value)) issues.add('At least one lowercase letter');
    if (!_uppercase.hasMatch(value)) issues.add('At least one uppercase letter');
    if (!_digit.hasMatch(value)) issues.add('At least one digit');
    if (!_specialChar.hasMatch(value)) issues.add('At least one special character');
    return issues;
  }

  static String? password(String? value) {
    final issues = passwordRequirementIssues(value ?? '');
    if (issues.isEmpty) return null;
    return 'Password does not meet all requirements';
  }

  static String? Function(String?) confirmPassword(String Function() password) {
    return (value) {
      if (value != password()) return 'Passwords do not match';
      return null;
    };
  }
}
