import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lewogram_client/app/app.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/storage/token_storage.dart';
import 'package:lewogram_client/core/theme/theme_controller.dart';

void main() {
  testWidgets('LeWoGramApp стартует без исключения', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    final navigatorKey = GlobalKey<NavigatorState>();
    final tokenStorage = TokenStorage();
    final apiClient = ApiClient(tokenStorage: tokenStorage);
    final themeController = ThemeController();
    await themeController.load();

    await tester.pumpWidget(
      AppScope(
        tokenStorage: tokenStorage,
        apiClient: apiClient,
        themeController: themeController,
        child: LeWoGramApp(
          navigatorKey: navigatorKey,
          apiClient: apiClient,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
