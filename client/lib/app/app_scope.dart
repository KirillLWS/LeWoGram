import 'package:flutter/material.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/storage/token_storage.dart';

/// Корень зависимостей: [TokenStorage] и [ApiClient] без сторонних DI-пакетов.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.tokenStorage,
    required this.apiClient,
    required super.child,
  });

  final TokenStorage tokenStorage;
  final ApiClient apiClient;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope не найден над виджетом');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      tokenStorage != oldWidget.tokenStorage ||
      apiClient != oldWidget.apiClient;
}
