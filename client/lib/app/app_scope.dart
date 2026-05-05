import 'package:flutter/material.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/storage/token_storage.dart';
import 'package:lewogram_client/core/theme/theme_controller.dart';

/// Корень зависимостей: [TokenStorage], [ApiClient] и [ThemeController] без сторонних DI-пакетов.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.tokenStorage,
    required this.apiClient,
    required this.themeController,
    required super.child,
  });

  final TokenStorage tokenStorage;
  final ApiClient apiClient;
  final ThemeController themeController;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope не найден над виджетом');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      tokenStorage != oldWidget.tokenStorage ||
      apiClient != oldWidget.apiClient ||
      themeController != oldWidget.themeController;
}
