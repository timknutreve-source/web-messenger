/// Base type for errors surfaced by the API service layer.
///
/// [message] is safe to show directly to the user.
sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NetworkUnavailableException extends AppException {
  const NetworkUnavailableException()
      : super('Could not reach the backend server. Make sure it is running.');
}

class RequestTimeoutException extends AppException {
  const RequestTimeoutException()
      : super('The request timed out. Please try again.');
}

class InvalidResponseException extends AppException {
  const InvalidResponseException()
      : super('The backend returned an unexpected response.');
}

class UnexpectedStatusException extends AppException {
  const UnexpectedStatusException(this.statusCode)
      : super('The backend returned an unexpected status code ($statusCode).');

  final int statusCode;
}
