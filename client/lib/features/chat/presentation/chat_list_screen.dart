import 'package:flutter/material.dart';
import 'package:lewogram_client/core/refresh/auto_refresh_mixin.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/features/chat/data/chat_models.dart';
import 'package:lewogram_client/features/chat/presentation/chat_avatar.dart';
import 'package:lewogram_client/features/chat/presentation/chat_screen.dart';

/// Список чатов. [apiClient] передаётся снаружи (координатор / экран после входа),
/// т.к. в этом модуле нет доступа к `InheritedWidget` с зависимостями.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({
    super.key,
    required this.apiClient,
    this.onStartChat,
  });

  final ApiClient apiClient;

  /// Если задан — показывается FAB «новый чат» (колбэк задаёт координатор).
  final VoidCallback? onStartChat;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with AutoRefreshMixin {
  List<ChatItem> _chats = [];
  bool _loading = true;
  String? _error;

  @override
  Duration get refreshInterval => const Duration(seconds: 8);

  @override
  Future<void> performRefresh() => _loadChats(silent: true);

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  /// Загрузка списка с сервера ([ApiClient.getChats]).
  /// При [silent] не включается полноэкранный индикатор (фоновое обновление).
  Future<void> _loadChats({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = await widget.apiClient.getChats();
      if (!mounted) return;
      setState(() {
        _chats = raw
            .map(
              (e) => ChatItem.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.toString();
      });
    }
  }

  String? _shortTime(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd.$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Чаты',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.25,
          ),
        ),
      ),
      floatingActionButton: widget.onStartChat == null
          ? null
          : FloatingActionButton(
              onPressed: widget.onStartChat,
              tooltip: 'Новый чат',
              child: const Icon(Icons.chat_outlined),
            ),
      body: _buildBody(theme, cs),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme cs) {
    if (_loading && _chats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _chats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.error),
          ),
        ),
      );
    }
    if (_chats.isEmpty) {
      return Center(
        child: Text(
          'Нет чатов',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadChats,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        itemCount: _chats.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final c = _chats[index];
          final preview = c.lastMessageText?.trim() ?? '';
          final subtitle = c.displaySubtitle?.trim();
          final timeStr = _shortTime(c.lastMessageCreatedAt);
          final unread = c.unreadCount;

          return Material(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.of(context)
                    .push<void>(
                  MaterialPageRoute<void>(
                    builder: (ctx) => ChatScreen(
                      chatId: c.id,
                      apiClient: widget.apiClient,
                      chatType: c.type,
                      peerUserId: c.peerUserId,
                      initialDisplayTitle: c.displayTitle,
                      initialTitle: c.title,
                      initialAvatarPath: c.avatarPath,
                      peerLogin: c.peerLogin,
                      peerDisplayName: c.peerDisplayName,
                    ),
                  ),
                )
                    .then((_) => _loadChats());
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChatAvatarCircle(
                      letter: chatAvatarLetter(c.resolvedTitle),
                      avatarPath: c.avatarPath,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(
                                child: Text(
                                  c.resolvedTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: unread > 0
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              if (timeStr != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  timeStr,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (subtitle != null && subtitle.isNotEmpty) ...[
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            preview.isEmpty ? 'Нет сообщений' : preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.35,
                              fontWeight:
                                  unread > 0 ? FontWeight.w500 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (unread > 0)
                      _UnreadBadge(count: unread, theme: theme),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({
    required this.count,
    required this.theme,
  });

  final int count;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: cs.onPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
