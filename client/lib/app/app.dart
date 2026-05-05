import 'package:flutter/material.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/app/home_shell.dart';
import 'package:lewogram_client/app/session_gate.dart';
import 'package:lewogram_client/features/admin/presentation/invites_screen.dart';
import 'package:lewogram_client/features/auth/presentation/login_screen.dart';
import 'package:lewogram_client/features/auth/presentation/register_screen.dart';

/// Material 3 и маршруты: заставка сессии, вход, регистрация, домашняя оболочка.
class LeWoGramApp extends StatefulWidget {
  const LeWoGramApp({
    super.key,
    required this.navigatorKey,
    required this.apiClient,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final ApiClient apiClient;

  @override
  State<LeWoGramApp> createState() => _LeWoGramAppState();
}

class _LeWoGramAppState extends State<LeWoGramApp> {
  @override
  void dispose() {
    widget.apiClient.dispose();
    super.dispose();
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SessionGate(),
        );
      case '/login':
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const LoginScreen(),
        );
      case '/register':
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const RegisterScreen(),
        );
      case '/home':
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const HomeShell(),
        );
      case '/invites':
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (ctx) => InvitesScreen(
            apiClient: AppScope.of(ctx).apiClient,
          ),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      title: 'LeWoGram',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
    );
  }
}
