import 'package:flutter/material.dart';

/// Карточка пользователя (заглушка): действия только через колбэки — API подключит координатор.
class OwnerUserDetailScreen extends StatelessWidget {
  const OwnerUserDetailScreen({
    super.key,
    required this.userId,
    required this.displayLabel,
    this.onGrantRole,
    this.onOpenHiddenChat,
    this.onRevokeRole,
  });

  final String userId;
  final String displayLabel;

  final void Function(String userId, String role)? onGrantRole;
  final void Function(String userId)? onOpenHiddenChat;
  final void Function(String userId)? onRevokeRole;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(displayLabel),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ID: $userId',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Действия',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: onGrantRole == null
                        ? null
                        : () => _pickRoleAndGrant(context),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Назначить роль'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: onOpenHiddenChat == null
                        ? null
                        : () => onOpenHiddenChat!(userId),
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: const Text('Скрытый чат модерации'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: onRevokeRole == null
                        ? null
                        : () => onRevokeRole!(userId),
                    icon: const Icon(Icons.remove_moderator_outlined),
                    label: const Text('Снять роль'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRoleAndGrant(BuildContext context) async {
    final role = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final roles = ['member', 'moderator', 'admin'];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: roles
                .map(
                  (r) => ListTile(
                    title: Text(r),
                    onTap: () => Navigator.pop(ctx, r),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
    if (role != null && context.mounted) {
      onGrantRole?.call(userId, role);
    }
  }
}
