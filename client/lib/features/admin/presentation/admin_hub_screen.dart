import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/storage/account_storage.dart';
import 'package:lewogram_client/features/admin/presentation/audit_events_screen.dart';
import 'package:lewogram_client/features/admin/presentation/device_transfers_screen.dart';
import 'package:lewogram_client/features/admin/presentation/invites_screen.dart';
import 'package:lewogram_client/features/admin/presentation/support_access_sessions_screen.dart';
import 'package:lewogram_client/features/admin/presentation/staff_users_screen.dart';
import 'package:lewogram_client/features/admin/presentation/support_diagnostics_screen.dart';
import 'package:lewogram_client/features/support/presentation/admin_support_tickets_screen.dart';
import 'package:lewogram_client/features/admin/presentation/support_login_logs_screen.dart';
import 'package:lewogram_client/features/chat/data/chat_models.dart';
import 'package:lewogram_client/features/chat/presentation/chat_screen.dart';

Future<void> navigateSupportChat(BuildContext context) async {
  final api = AppScope.of(context).apiClient;
  try {
    final me = await api.getMe();
    if (!context.mounted) return;
    final primary = me['primary_role']?.toString().trim();
    final staff = {'owner', 'chief_admin', 'admin'}.contains(primary);
    final raw = await api.getSupportChat();
    if (!context.mounted) return;
    final m = Map<String, dynamic>.from(raw);
    final id = (m['id'] as num).toInt();
    final title = ChatItem.fromJson(m).resolvedTitle;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          chatId: id,
          apiClient: api,
          chatType: 'support',
          allowSupportStaffReply: staff,
          initialDisplayTitle: title,
        ),
      ),
    );
  } on ApiException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Тело админ-хаба (без вложенного [Scaffold]) — для встраивания во вкладку владельца.
class AdminHubBody extends StatelessWidget {
  const AdminHubBody({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<Map<String, dynamic>?>(
      future: AccountStorage.read(),
      builder: (context, snap) {
        final p = snap.data?['primary_role']?.toString().trim();
        final showDiagnostics = p == 'owner' || p == 'chief_admin';
        final showOwnerLogs = p == 'owner';

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.add_link, color: scheme.primary),
                    title: const Text('Инвайты и регистрация'),
                    subtitle:
                        const Text('Создать токен для нового пользователя'),
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
                    leading:
                        Icon(Icons.support_agent, color: scheme.primary),
                    title: const Text('Поддержка'),
                    subtitle: const Text(
                      'Все тикеты поддержки, сгруппированные по пользователям',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminSupportTicketsScreen(),
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
                    leading: Icon(Icons.phonelink_setup_outlined,
                        color: scheme.primary),
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
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.support_agent_outlined,
                        color: scheme.primary),
                    title: const Text('Чат поддержки'),
                    subtitle: const Text(
                        'Все пользователи; ответ по цитате — admin+'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => navigateSupportChat(context),
                  ),
                  if (showDiagnostics) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.receipt_long_outlined,
                          color: scheme.primary),
                      title: const Text('Журнал диагностики'),
                      subtitle: const Text('Отправленные пользователями логи'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const SupportDiagnosticsScreen(),
                          ),
                        );
                      },
                    ),
                    if (showOwnerLogs) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.privacy_tip_outlined,
                            color: scheme.primary),
                        title: const Text('Активные доступы диагностики'),
                        subtitle: const Text(
                            'Кто дал временное согласие на расширенные логи'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const SupportAccessSessionsScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.manage_search_outlined,
                            color: scheme.primary),
                        title: const Text('Серверные логи входов'),
                        subtitle: const Text(
                            'IP, fingerprint и результат авторизации'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => const SupportLoginLogsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                    const Divider(height: 1),
                    ListTile(
                      leading:
                          Icon(Icons.history_outlined, color: scheme.primary),
                      title: const Text('Журнал аудита'),
                      subtitle:
                          const Text('Входы, роли, сброс сессий, диагностика'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const AuditEventsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Админ-хаб: инвайты и смена устройств (этап 2).
class AdminHubScreen extends StatelessWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Админ')),
      body: const AdminHubBody(),
    );
  }
}
