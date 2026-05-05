import 'package:flutter/material.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/app/app_scope.dart';

/// Заставка: проверка токена и маршрут на вход или домашнюю оболочку.
class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final scope = AppScope.of(context);
    final nav = Navigator.of(context);
    final token = await scope.tokenStorage.readToken();
    if (!mounted) return;

    if (token == null || token.isEmpty) {
      nav.pushReplacementNamed('/login');
      return;
    }

    try {
      await scope.apiClient.getMe();
      if (!mounted) return;
      nav.pushReplacementNamed('/home');
    } on UnauthorizedException catch (_) {
      if (!mounted) return;
      await scope.tokenStorage.clearToken();
      nav.pushReplacementNamed('/login');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        await scope.tokenStorage.clearToken();
      }
      nav.pushReplacementNamed('/login');
    } catch (_) {
      if (!mounted) return;
      nav.pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
