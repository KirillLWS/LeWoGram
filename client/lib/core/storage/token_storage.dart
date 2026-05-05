import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Хранение JWT (Android Keystore / EncryptedSharedPreferences).
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyJwt = 'lewogram_jwt';

  final FlutterSecureStorage _storage;

  Future<void> saveToken(String token) =>
      _storage.write(key: _keyJwt, value: token);

  Future<String?> readToken() => _storage.read(key: _keyJwt);

  Future<void> clearToken() => _storage.delete(key: _keyJwt);
}
