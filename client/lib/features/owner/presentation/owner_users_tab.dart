import 'package:flutter/material.dart';
import 'package:lewogram_client/features/owner/presentation/owner_user_detail_screen.dart';

/// Вкладка «Пользователи»: список-заглушка и переход в детальную заглушку.
class OwnerUsersTab extends StatelessWidget {
  const OwnerUsersTab({
    super.key,
    this.onGrantRole,
    this.onOpenHiddenChat,
    this.onRevokeRole,
  });

  final void Function(String userId, String role)? onGrantRole;
  final void Function(String userId)? onOpenHiddenChat;
  final void Function(String userId)? onRevokeRole;

  static const _stubUsers = <({String id, String title})>[
    (id: 'stub_u1', title: 'Пользователь 1'),
    (id: 'stub_u2', title: 'Пользователь 2'),
    (id: 'stub_u3', title: 'Пользователь 3'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      itemCount: _stubUsers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final u = _stubUsers[index];
        return Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: CircleAvatar(
              child: Text('${index + 1}'),
            ),
            title: Text(u.title),
            subtitle: Text(
              u.id,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => OwnerUserDetailScreen(
                    userId: u.id,
                    displayLabel: u.title,
                    onGrantRole: onGrantRole,
                    onOpenHiddenChat: onOpenHiddenChat,
                    onRevokeRole: onRevokeRole,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
