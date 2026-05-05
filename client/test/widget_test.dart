import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lewogram_client/app/app.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/storage/token_storage.dart';

void main() {
  testWidgets('LeWoGramApp стартует без исключения', (WidgetTester tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final tokenStorage = TokenStorage();
    final apiClient = ApiClient(tokenStorage: tokenStorage);

    await tester.pumpWidget(
      AppScope(
        tokenStorage: tokenStorage,
        apiClient: apiClient,
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
