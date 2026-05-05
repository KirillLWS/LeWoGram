import 'package:flutter/material.dart';
import 'package:lewogram_client/features/owner/presentation/owner_hidden_moderation_screen.dart';

/// Вкладка «Чаты»: все чаты сервера (заглушка списка) и скрытый просмотр модерации.
class OwnerChatsTab extends StatelessWidget {
  const OwnerChatsTab({
    super.key,
    this.onJoinAsParticipant,
  });

  final void Function(String chatId)? onJoinAsParticipant;

  static const _stubChats = <({String id, String title})>[
    (id: 'stub_c1', title: 'Чат сервера 1'),
    (id: 'stub_c2', title: 'Чат сервера 2'),
    (id: 'stub_c3', title: 'Чат сервера 3'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      itemCount: _stubChats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final c = _stubChats[index];
        return Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Icon(Icons.forum_outlined, color: cs.primary),
            title: Text(c.title),
            subtitle: Text(
              c.id,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.shield_outlined),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => OwnerHiddenModerationScreen(
                    chatId: c.id,
                    chatTitle: c.title,
                    onJoinAsParticipant: onJoinAsParticipant,
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
