import '../../../core/network/app_exception.dart';

class AuthErrorPresentation {
  const AuthErrorPresentation({required this.message, this.fieldErrors = const {}});

  final String message;
  final Map<String, String> fieldErrors;
}

/// Converts an error thrown by [AuthController.login]/[AuthController.register]
/// into a message safe to show the user, plus any per-field validation errors.
AuthErrorPresentation presentAuthError(Object error) {
  if (error is ValidationException) {
    return AuthErrorPresentation(message: error.message, fieldErrors: error.fieldErrors);
  }
  if (error is AppException) {
    return AuthErrorPresentation(message: error.message);
  }
  return const AuthErrorPresentation(message: 'Something went wrong. Please try again.');
}
