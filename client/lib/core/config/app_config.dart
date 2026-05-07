/// Единая точка настройки API для MVP.
class AppConfig {
  /// Базовый URL без завершающего `/`.
  ///
  /// Эмулятор: `http://10.0.2.2:8000` (localhost машины с сервером).
  /// Реальный телефон: IP ПК в LAN (тот же Wi‑Fi, что и телефон).
  static const String baseUrl = 'http://192.168.0.111:8000';

  /// Локальная разработка без сервера: `--dart-define=SKIP_CLIENT_VERSION_CHECK=true`.
  static const bool skipClientVersionCheck = bool.fromEnvironment(
    'SKIP_CLIENT_VERSION_CHECK',
    defaultValue: false,
  );
}
