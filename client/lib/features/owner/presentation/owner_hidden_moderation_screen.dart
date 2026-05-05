import 'package:flutter/material.dart';

/// Скрытый режим модерации: только чтение, список сообщений-заглушек.
class OwnerHiddenModerationScreen extends StatelessWidget {
  const OwnerHiddenModerationScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
    this.onJoinAsParticipant,
  });

  final String chatId;
  final String chatTitle;

  /// «Вступить как участник» — вызывает координатор (подключение к обычному чату).
  final void Function(String chatId)? onJoinAsParticipant;

  static const _stubMessages = <String>[
    '[заглушка] Системное сообщение',
    '[заглушка] Пользователь: пример текста',
    '[заглушка] Ещё одно сообщение для списка',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chatTitle),
            Text(
              'Модерация · $chatId',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: onJoinAsParticipant == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => onJoinAsParticipant!(chatId),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Вступить как участник'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Card(
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Только просмотр. Отправка сообщений недоступна в режиме модерации.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _stubMessages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final text = _stubMessages[index];
                return Align(
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        text,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
