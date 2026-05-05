import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Кэш последнего ответа [/auth/me] для оболочки и профиля (ник / аватар не «слетят»).
class AccountStorage {
  AccountStorage._();

  static const _key = 'lewogram_account_me_v1';

  static Future<void> upsert(Map<String, dynamic> me) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(me));
  }

  static Future<Map<String, dynamic>?> read() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key);
    if (s == null || s.isEmpty) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
