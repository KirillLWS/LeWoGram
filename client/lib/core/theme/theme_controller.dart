import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lewogram_client/core/theme/app_themes.dart';

/// Текущая тема приложения: хранение в SharedPreferences и [notifyListeners].
class ThemeController extends ChangeNotifier {
  ThemeController();

  static const String _prefsKey = 'lewogram_theme_kind';

  AppThemeKind _kind = AppThemeKind.defaultLight;

  AppThemeKind get kind => _kind;

  ThemeData get themeData => AppThemes.theme(_kind);

  /// Загрузить сохранённую тему (вызвать из [main] до [runApp]).
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _kind = AppThemeKindStorage.parse(p.getString(_prefsKey));
    notifyListeners();
  }

  Future<void> setTheme(AppThemeKind kind) async {
    _kind = kind;
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, kind.name);
    notifyListeners();
  }

  Future<void> resetToDefault() => setTheme(AppThemeKind.defaultLight);
}
