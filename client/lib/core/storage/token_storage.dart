import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Хранение JWT и refresh (Android Keystore / EncryptedSharedPreferences).
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyJwt = 'lewogram_jwt';
  static const _keyRefresh = 'lewogram_refresh';

  final FlutterSecureStorage _storage;

  Future<void> saveToken(String token) =>
      _storage.write(key: _keyJwt, value: token);

  Future<String?> readToken() => _storage.read(key: _keyJwt);

  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _keyRefresh, value: token);

  Future<String?> readRefreshToken() => _storage.read(key: _keyRefresh);

  Future<void> clearToken() async {
    await _storage.delete(key: _keyJwt);
    await _storage.delete(key: _keyRefresh);
  }
}
