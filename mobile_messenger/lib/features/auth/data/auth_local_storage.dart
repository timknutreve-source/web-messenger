import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the JWT (and only the JWT - never the password) between app
/// launches using the platform's secure storage.
class AuthLocalStorage {
  AuthLocalStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}
