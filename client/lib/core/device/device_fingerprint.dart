import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Стабильный отпечаток устройства для [LoginRequest.device_fingerprint].
/// Генерируется один раз и хранится в secure storage.
class DeviceFingerprint {
  DeviceFingerprint({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'lewogram_device_fingerprint_v1';

  final FlutterSecureStorage _storage;

  /// Возвращает сохранённый или новый отпечаток.
  Future<String> getOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) return existing;
    final fp = _generate();
    await _storage.write(key: _key, value: fp);
    return fp;
  }

  String _generate() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
