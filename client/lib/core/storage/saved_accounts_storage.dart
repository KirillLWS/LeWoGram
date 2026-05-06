import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Сохранённые сессии на устройстве: логин + токены (тот же keystore, что и [TokenStorage]).
class SavedAccountsStorage {
  SavedAccountsStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _indexKey = 'lewogram_saved_accounts_index_v1';

  final FlutterSecureStorage _storage;

  String _rowKey(String login) => 'lewogram_saved_row_${login.hashCode}';

  Future<List<SavedAccountRow>> listRows() async {
    final raw = await _storage.read(key: _indexKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List<dynamic>) return [];
      return list
          .map((e) {
            if (e is! Map<String, dynamic>) return null;
            final login = e['login']?.toString();
            if (login == null || login.isEmpty) return null;
            return SavedAccountRow(
              login: login,
              label: e['label']?.toString(),
            );
          })
          .whereType<SavedAccountRow>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCurrentSession({
    required String login,
    required String accessToken,
    required String refreshToken,
    String? displayLabel,
  }) async {
    final rows = await listRows();
    final label = (displayLabel ?? login).trim();
    final next = <Map<String, dynamic>>[
      {'login': login, 'label': label},
      ...rows.where((r) => r.login != login).map((r) => {'login': r.login, 'label': r.label ?? r.login}),
    ];
    await _storage.write(
      key: _rowKey(login),
      value: jsonEncode({
        'access_token': accessToken,
        'refresh_token': refreshToken,
      }),
    );
    await _storage.write(key: _indexKey, value: jsonEncode(next));
  }

  Future<({String access, String refresh})?> readTokens(String login) async {
    final raw = await _storage.read(key: _rowKey(login));
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return null;
      final a = m['access_token']?.toString();
      final r = m['refresh_token']?.toString();
      if (a == null || r == null || a.isEmpty || r.isEmpty) return null;
      return (access: a, refresh: r);
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String login) async {
    final rows = await listRows();
    final next = rows.where((r) => r.login != login).map((r) => {'login': r.login, 'label': r.label ?? r.login}).toList();
    await _storage.delete(key: _rowKey(login));
    await _storage.write(key: _indexKey, value: jsonEncode(next));
  }

  Future<void> clearAll() async {
    final rows = await listRows();
    for (final r in rows) {
      await _storage.delete(key: _rowKey(r.login));
    }
    await _storage.delete(key: _indexKey);
  }
}

class SavedAccountRow {
  SavedAccountRow({required this.login, this.label});

  final String login;
  final String? label;
}
