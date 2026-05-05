import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/push/push_service.dart';
import 'package:lewogram_client/features/chat/presentation/chat_list_screen.dart';
import 'package:lewogram_client/features/profile/presentation/profile_screen.dart';

bool _canManageInvites(List<String> roles) {
  return roles.contains('owner') || roles.contains('chief_admin');
}

/// Авторизованная оболочка: чаты и профиль с нижней навигацией.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // У пользователя уже есть JWT — регистрируем FCM после первого кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final api = AppScope.of(context).apiClient;
      PushService.initAndGetToken(api);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final api = scope.apiClient;

    final pages = <Widget>[
      ChatListScreen(apiClient: api),
      ProfileScreen(
        apiClient: api,
        loadRoles: () async {
          try {
            final m = await api.getMe();
            final r = m['roles'];
            if (r is List) {
              return r.map((e) => e.toString()).toList();
            }
          } catch (_) {}
          return <String>[];
        },
        invitesEligibility: _canManageInvites,
        onOpenInvites: () {
          Navigator.of(context).pushNamed('/invites');
        },
        onLogout: () async {
          await scope.tokenStorage.clearToken();
          if (!context.mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        },
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Чаты',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}
