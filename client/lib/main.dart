import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/storage/token_storage.dart';
import 'package:lewogram_client/core/theme/theme_controller.dart';
import 'package:lewogram_client/app/app.dart';
import 'package:lewogram_client/app/app_scope.dart';

/// Ключ навигатора для реакции ApiClient на 401 (сброс стека до экрана входа).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Точка входа: binding, Firebase, синглтоны хранилища и API, обёртка [AppScope].
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase: на Android после добавления google-services.json из консоли Firebase.
  // Без конфигурации инициализация может упасть — приложение всё равно запускается.
  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    debugPrint('Firebase.initializeApp: $e\n$st');
  }

  final tokenStorage = TokenStorage();
  final themeController = ThemeController();
  await themeController.load();

  final apiClient = ApiClient(
    tokenStorage: tokenStorage,
    onUnauthorized: () {
      appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    },
  );

  runApp(
    AppScope(
      tokenStorage: tokenStorage,
      apiClient: apiClient,
      themeController: themeController,
      child: LeWoGramApp(
        navigatorKey: appNavigatorKey,
        apiClient: apiClient,
      ),
    ),
  );
}
