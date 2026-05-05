import 'package:flutter/material.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Скрытый режим модерации: read-only история чата (через /owner/server-chats/{id}/messages).
class OwnerHiddenModerationScreen extends StatefulWidget {
  const OwnerHiddenModerationScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
    required this.apiClient,
    this.onJoinAsParticipant,
  });

  final String chatId;
  final String chatTitle;
  final ApiClient apiClient;

  /// «Вступить как участник» — вызывает координатор (подключение к обычному чату).
  final void Function(String chatId)? onJoinAsParticipant;

  @override
  State<OwnerHiddenModerationScreen> createState() =>
      _OwnerHiddenModerationScreenState();
}

class _OwnerHiddenModerationScreenState
    extends State<OwnerHiddenModerationScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = int.tryParse(widget.chatId) ?? 0;
      final raw = await widget.apiClient.ownerServerChatMessages(id);
      if (!mounted) return;
      setState(() {
        _messages = raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final l = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget body;
    if (_loading && _messages.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _messages.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _load,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    } else if (_messages.isEmpty) {
      body = Center(
        child: Text(
          'Сообщений пока нет',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _messages.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final m = _messages[index];
            final senderId = (m['sender_id'] as num?)?.toInt();
            final type = m['type']?.toString() ?? '';
            final text = m['text']?.toString() ?? '';
            final created = _formatTime(m['created_at']?.toString() ?? '');
            return Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.85,
                ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'sender ${senderId ?? '-'} · $type',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          SelectableText(
                            text,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                        if (created.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            created,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chatTitle),
            Text(
              'Модерация · ${widget.chatId}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: widget.onJoinAsParticipant == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => widget.onJoinAsParticipant!(widget.chatId),
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
          Expanded(child: body),
        ],
      ),
    );
  }
}
