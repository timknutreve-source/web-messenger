/// Base type for errors surfaced by the API service layer.
///
/// [message] is safe to show directly to the user.
sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Never mentions "backend"/"server" or any other technical/infrastructure
/// detail to the user - see the README's Login UI section. [statusCode] is
/// still recorded on [UnexpectedStatusException] for developers (logs,
/// debugging), just never surfaced in the displayed [message].
class NetworkUnavailableException extends AppException {
  const NetworkUnavailableException() : super('Unable to connect. Please try again.');
}

class RequestTimeoutException extends AppException {
  const RequestTimeoutException() : super('Unable to connect. Please try again.');
}

class InvalidResponseException extends AppException {
  const InvalidResponseException() : super('Something went wrong. Please try again.');
}

class UnexpectedStatusException extends AppException {
  const UnexpectedStatusException(this.statusCode) : super('Something went wrong. Please try again.');

  final int statusCode;
}

/// A `400` response: request body failed server-side validation.
///
/// [fieldErrors] maps field name (e.g. `"email"`) to a human-readable message,
/// as returned by the backend's validation error body.
class ValidationException extends AppException {
  const ValidationException(super.message, this.fieldErrors);

  final Map<String, String> fieldErrors;
}

/// A `401` response for a login attempt or an unauthenticated request.
class InvalidCredentialsException extends AppException {
  const InvalidCredentialsException([String? message])
      : super(message ?? 'Invalid credentials.');
}

/// A `409` response: the email or username is already taken.
class DuplicateResourceException extends AppException {
  const DuplicateResourceException([String? message])
      : super(message ?? 'That account already exists.');
}

/// A `5xx` response.
class ServerErrorException extends AppException {
  const ServerErrorException()
      : super('Something went wrong on our end. Please try again later.');
}

/// A `413` response: an uploaded file exceeded the server's size limit.
class FileTooLargeException extends AppException {
  const FileTooLargeException([String? message])
      : super(message ?? 'That file is too large.');
}
