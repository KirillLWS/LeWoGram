import 'package:flutter/material.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/features/settings/presentation/settings_screen.dart';
import 'package:lewogram_client/app/home_shell.dart';
import 'package:lewogram_client/app/session_gate.dart';
import 'package:lewogram_client/features/admin/presentation/invites_screen.dart';
import 'package:lewogram_client/features/admin/presentation/device_transfers_screen.dart';
import 'package:lewogram_client/features/auth/presentation/login_screen.dart';
import 'package:lewogram_client/features/auth/presentation/register_screen.dart';
import 'package:lewogram_client/features/device_transfer/presentation/device_transfer_request_screen.dart';
import 'package:lewogram_client/features/device_transfer/presentation/device_transfer_wait_screen.dart';
import 'package:lewogram_client/features/onboarding/presentation/permissions_onboarding_screen.dart';

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
      case '/onboarding-permissions':
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const PermissionsOnboardingScreen(),
        );
      case '/invites':
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (ctx) => InvitesScreen(
            apiClient: AppScope.of(ctx).apiClient,
          ),
        );
      case '/settings':
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SettingsScreen(),
        );
      case '/device-transfer-request':
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) {
            final a = settings.arguments;
            String? login;
            String? password;
            if (a is Map) {
              if (a['login'] is String) login = a['login'] as String;
              if (a['password'] is String) password = a['password'] as String;
            }
            return DeviceTransferRequestScreen(
              initialLogin: login,
              initialPassword: password,
            );
          },
        );
      case '/device-transfer-wait':
        final waitArgs = settings.arguments;
        if (waitArgs is Map<String, dynamic> &&
            waitArgs['requestId'] is num &&
            waitArgs['shortCode'] is String) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => DeviceTransferWaitScreen(
              requestId: (waitArgs['requestId'] as num).toInt(),
              shortCode: waitArgs['shortCode'] as String,
            ),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Scaffold(
            body: Center(child: Text('Некорректные параметры маршрута')),
          ),
        );
      case '/device-transfers-admin':
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const DeviceTransfersScreen(),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = AppScope.of(context).themeController;
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: widget.navigatorKey,
          title: 'LeWoGram',
          theme: themeController.themeData,
          initialRoute: '/',
          onGenerateRoute: _onGenerateRoute,
        );
      },
    );
  }
}
