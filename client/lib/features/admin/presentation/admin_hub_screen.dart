import 'package:flutter/material.dart';
import 'package:lewogram_client/features/admin/presentation/device_transfers_screen.dart';
import 'package:lewogram_client/features/admin/presentation/invites_screen.dart';
import 'package:lewogram_client/features/admin/presentation/staff_users_screen.dart';
import 'package:lewogram_client/app/app_scope.dart';

/// Админ-хаб: инвайты и смена устройств (этап 2).
class AdminHubScreen extends StatelessWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Админ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.add_link, color: scheme.primary),
                  title: const Text('Инвайты и регистрация'),
                  subtitle: const Text('Создать токен для нового пользователя'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (ctx) => InvitesScreen(
                          apiClient: AppScope.of(ctx).apiClient,
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.people_outline, color: scheme.primary),
                  title: const Text('Пользователи сервера'),
                  subtitle: const Text(
                    'Список всех аккаунтов, блокировка и разблокировка',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const StaffUsersListScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.phonelink_setup_outlined, color: scheme.primary),
                  title: const Text('Смена устройства'),
                  subtitle: const Text(
                    'Подтвердить или отклонить вход с нового устройства',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const DeviceTransfersScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
