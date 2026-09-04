import 'app_exception.dart';

class ErrorPresentation {
  const ErrorPresentation({required this.message, this.fieldErrors = const {}});

  final String message;
  final Map<String, String> fieldErrors;
}

/// Converts an error thrown by an API service call into a message safe to
/// show the user, plus any per-field validation errors. Shared by every
/// feature that surfaces backend errors in a form (auth, profile, ...).
ErrorPresentation presentError(Object error) {
  if (error is ValidationException) {
    return ErrorPresentation(message: error.message, fieldErrors: error.fieldErrors);
  }
  if (error is AppException) {
    return ErrorPresentation(message: error.message);
  }
  return const ErrorPresentation(message: 'Something went wrong. Please try again.');
}
