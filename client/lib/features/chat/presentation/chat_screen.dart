import 'package:flutter/material.dart';
import 'package:lewogram_client/core/refresh/auto_refresh_mixin.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/features/chat/data/chat_models.dart';
import 'package:lewogram_client/features/chat/presentation/chat_avatar.dart';
import 'package:lewogram_client/features/users/data/user_public_profile.dart';
import 'package:lewogram_client/features/users/presentation/user_profile_screen.dart';

bool _userPublicMapIndicatesBanned(Map<String, dynamic> raw) {
  final st = raw['account_status'] as String? ?? 'active';
  if (st == 'banned' || st == 'temp_banned') return true;
  final ib = raw['is_blocked'];
  if (ib is num) return ib != 0;
  if (ib is bool) return ib;
  return false;
}

/// Экран переписки по [chatId]. Сообщения подгружаются через [ApiClient.getMessages],
/// отправка — [ApiClient.sendText].
///
/// [currentUserId] можно передать из списка после [ApiClient.getMe]; если `null`,
/// экран один раз запросит [/auth/me] при первом [didChangeDependencies].
///
/// Заголовок AppBar: приоритет локального переименования → [initialDisplayTitle] →
/// [initialTitle] → peer → «Чат #id».
/// [chatType] и [peerUserId] для direct: кнопка «Профиль» и переход на экран пользователя.
/// Если [peerUserId] не передан, для личного чата можно определить собеседника по сообщениям.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    required this.apiClient,
    this.currentUserId,
    this.chatType,
    this.peerUserId,
    this.initialDisplayTitle,
    this.initialTitle,
    this.initialAvatarPath,
    this.peerLogin,
    this.peerDisplayName,
  });

  final int chatId;
  final ApiClient apiClient;

  /// Если задан — сравнение «своё / чужое» без лишнего GET /me.
  final int? currentUserId;

  /// Например `direct` / `group` — для группы кнопка профиля собеседника скрыта.
  final String? chatType;

  /// Собеседник в личном чате (передаётся из списка или при открытии из друзей).
  final int? peerUserId;

  final String? initialDisplayTitle;
  final String? initialTitle;

  /// Аватар из списка чатов ([avatar_path]); показывается в AppBar при разрешимом URL.
  final String? initialAvatarPath;
  final String? peerLogin;
  final String? peerDisplayName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with AutoRefreshMixin {
  final _textCtrl = TextEditingController();
  List<MessageItem> _messages = [];
  bool _loading = true;
  String? _error;
  int? _currentUserId;

  @override
  Duration get refreshInterval => const Duration(seconds: 4);

  @override
  Future<void> performRefresh() => _loadMessages(silent: true);

  /// После успешного переименования (или ввод пользователя до появления API).
  String? _titleOverride;

  /// Последний message_id, для которого уже ушёл успешный mark-read (не дублировать запросы).
  int? _lastMarkReadSentForMessageId;

  /// Защита от параллельных POST /messages/mark-read.
  bool _markReadInProgress = false;

  /// Личный чат: собеседник под санкцией — блокируем ввод.
  bool _peerComposeBlocked = false;
  String? _peerComposeHint;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = widget.currentUserId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initUserAndMessages();
    });
  }

  String get _appBarTitle {
    final o = _titleOverride?.trim();
    if (o != null && o.isNotEmpty) return o;
    final d = widget.initialDisplayTitle?.trim();
    if (d != null && d.isNotEmpty) return d;
    final t = widget.initialTitle?.trim();
    if (t != null && t.isNotEmpty) return t;
    final pd = widget.peerDisplayName?.trim();
    if (pd != null && pd.isNotEmpty) return pd;
    final pl = widget.peerLogin?.trim();
    if (pl != null && pl.isNotEmpty) return pl;
    return 'Чат #${widget.chatId}';
  }

  /// Разовая идентификация «я» и первая загрузка истории.
  Future<void> _initUserAndMessages() async {
    if (_currentUserId == null) {
      try {
        final meMap = await widget.apiClient.getMe();
        if (!mounted) return;
        setState(() => _currentUserId = UserMe.fromJson(meMap).id);
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = e.message;
        });
        return;
      } on UnauthorizedException catch (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Сессия недействительна';
        });
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = e.toString();
        });
        return;
      }
    }
    if (mounted && _isDirectChat()) {
      await _refreshPeerComposeGate();
    }
    await _loadMessages();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  /// Загрузка сообщений чата.
  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = await widget.apiClient.getMessages(widget.chatId);
      if (!mounted) return;
      setState(() {
        _messages = raw
            .map(
              (e) => MessageItem.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
        _loading = false;
        _error = null;
      });
      await _syncMarkReadIfNeeded();
      await _refreshPeerComposeGate();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _loading = false;
        if (!silent) _error = e.message;
      });
    } on UnauthorizedException catch (_) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _loading = false;
          _error = 'Сессия недействительна';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _loading = false;
        if (!silent) _error = e.toString();
      });
    }
  }

  /// После загрузки ленты: считаем прочитанным последнее сообщение в списке (MVP).
  Future<void> _syncMarkReadIfNeeded() async {
    if (!mounted) return;
    if (_messages.isEmpty) return;
    if (_markReadInProgress) return;

    final lastId = _messages.last.id;
    if (_lastMarkReadSentForMessageId == lastId) return;

    _markReadInProgress = true;
    try {
      await widget.apiClient.markRead(widget.chatId, lastId);
      if (!mounted) return;
      _lastMarkReadSentForMessageId = lastId;
    } on ApiException catch (_) {
      // MVP: не блокируем UI; при следующем refresh/poll повторим (lastId тот же).
    } on UnauthorizedException catch (_) {
      // 401 обработан в ApiClient (сброс сессии).
    } finally {
      _markReadInProgress = false;
    }
  }

  Future<void> _send() async {
    if (_peerComposeBlocked) {
      final hint = _peerComposeHint?.trim();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hint != null && hint.isNotEmpty ? hint : 'Нельзя отправить сообщение: аккаунт заблокирован',
          ),
        ),
      );
      return;
    }
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await widget.apiClient.sendText(widget.chatId, text);
      if (!mounted) return;
      _textCtrl.clear();
      await _loadMessages(silent: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  bool _isOwnMessage(MessageItem m) {
    final me = _currentUserId;
    if (me == null) return false;
    return m.senderId == me;
  }

  bool _isDirectChat() {
    final t = widget.chatType?.trim().toLowerCase();
    if (t == null || t.isEmpty) return true;
    return t == 'direct';
  }

  int? _resolvedPeerUserId() {
    final w = widget.peerUserId;
    if (w != null) return w;
    if (!_isDirectChat()) return null;
    final me = _currentUserId;
    if (me == null) return null;
    for (final m in _messages) {
      final sid = m.senderId;
      if (sid != null && sid != me) return sid;
    }
    return null;
  }

  Future<void> _refreshPeerComposeGate() async {
    if (!mounted || !_isDirectChat()) return;
    final pid = _resolvedPeerUserId();
    if (pid == null) {
      setState(() {
        _peerComposeBlocked = false;
        _peerComposeHint = null;
      });
      return;
    }
    try {
      final raw = Map<String, dynamic>.from(
        await widget.apiClient.getUserPublic(pid) as Map,
      );
      if (!mounted) return;
      final banned = _userPublicMapIndicatesBanned(raw);
      final reason = raw['ban_reason'] as String? ?? '';
      setState(() {
        _peerComposeBlocked = banned;
        _peerComposeHint = banned
            ? (reason.trim().isNotEmpty ? reason.trim() : 'Собеседник заблокирован')
            : null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      setState(() {
        _peerComposeBlocked = false;
        _peerComposeHint = null;
      });
    } on UnauthorizedException catch (_) {
      if (!mounted) return;
      setState(() {
        _peerComposeBlocked = false;
        _peerComposeHint = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      setState(() {
        _peerComposeBlocked = false;
        _peerComposeHint = null;
      });
    }
  }

  Future<void> _openPeerProfile() async {
    final peerId = _resolvedPeerUserId();
    if (peerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось определить пользователя')),
      );
      return;
    }
    try {
      final raw = await widget.apiClient.getUserPublic(peerId);
      if (!mounted) return;
      final profile = UserPublicProfile.fromJson(Map<String, dynamic>.from(raw));
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (ctx) => UserProfileScreen(
            profile: profile,
            apiClient: widget.apiClient,
            onWrite: (otherUserId) async {
              Navigator.of(ctx).pop();
              if (otherUserId == peerId) return;
              try {
                final chat = await widget.apiClient.createDirectChat(otherUserId);
                if (!mounted) return;
                final id = (chat['id'] as num).toInt();
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatScreen(
                      chatId: id,
                      apiClient: widget.apiClient,
                      currentUserId: _currentUserId,
                      chatType: 'direct',
                      peerUserId: otherUserId,
                    ),
                  ),
                );
              } on ApiException catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _shortMessageTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    if (day == today) return '$h:$min';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd.$mm $h:$min';
  }

  Future<void> _showRenameDialog() async {
    // Controller must live in dialog [State] and be disposed there. Disposing it
    // in the parent as soon as [showDialog] completes runs before the route has
    // torn down [TextField], which can break InheritedWidget teardown
    // (debug: InheritedElement.debugDeactivated / _dependents.isEmpty).
    final next = await showDialog<String?>(
      context: context,
      builder: (ctx) => _ChatRenameDialog(initialTitle: _appBarTitle),
    );
    if (next == null || next.isEmpty || !mounted) return;
    try {
      await widget.apiClient.renameChat(widget.chatId, next);
      if (!mounted) return;
      final titleToApply = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _titleOverride = titleToApply);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Название обновлено')),
        );
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final peerForProfile = _resolvedPeerUserId();
    final showProfileAction = _isDirectChat() && peerForProfile != null;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (widget.initialAvatarPath?.trim().isNotEmpty ?? false) ...[
              ChatAvatarCircle(
                letter: chatAvatarLetter(_appBarTitle),
                avatarPath: widget.initialAvatarPath,
                radius: 16,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                _appBarTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (showProfileAction)
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Профиль',
              onPressed: _openPeerProfile,
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Переименовать',
            onPressed: _showRenameDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null && _messages.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: cs.error),
              ),
            ),
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadMessages,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                      final m = _messages[index];
                      final isMine = _isOwnMessage(m);
                      final text = m.text ?? '';
                      final timeStr = _shortMessageTime(m.createdAt);

                      final bubbleBg = isMine
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest;
                      final onBubble = isMine
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant;

                      final align =
                          isMine ? Alignment.centerRight : Alignment.centerLeft;
                      final crossMain = isMine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start;

                      final radius = BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMine ? 18 : 4),
                        bottomRight: Radius.circular(isMine ? 4 : 18),
                      );

                      final bubble = Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                        decoration: BoxDecoration(
                          color: bubbleBg,
                          borderRadius: radius,
                          boxShadow: [
                            BoxShadow(
                              color: cs.shadow.withValues(alpha: 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: crossMain,
                          children: [
                            SelectableText(
                              text,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: isMine ? cs.onPrimaryContainer : cs.onSurface,
                                height: 1.4,
                              ),
                            ),
                            if (timeStr.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                timeStr,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: onBubble.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );

                      return Align(
                        alignment: align,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.84,
                          ),
                          child: bubble,
                        ),
                      );
                    },
                  ),
                ),
          ),
          SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isDirectChat() && _peerComposeBlocked)
                  Material(
                    color: cs.errorContainer.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: cs.onErrorContainer, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _peerComposeHint ??
                                  (_peerComposeBlocked ? 'Нельзя отправлять сообщения' : ''),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textCtrl,
                          enabled: !_peerComposeBlocked,
                          decoration: InputDecoration(
                            hintText: 'Сообщение…',
                            filled: true,
                            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: cs.outlineVariant),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: cs.primary, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            isDense: true,
                          ),
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      FilledButton(
                        onPressed: _peerComposeBlocked ? null : _send,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(14),
                          shape: const CircleBorder(),
                        ),
                        child: const Icon(Icons.send, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatRenameDialog extends StatefulWidget {
  const _ChatRenameDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_ChatRenameDialog> createState() => _ChatRenameDialogState();
}

class _ChatRenameDialogState extends State<_ChatRenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Название чата'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Отображаемое имя',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.sentences,
        maxLines: 1,
        onSubmitted: (_) {
          final t = _controller.text.trim();
          if (t.isEmpty) return;
          if (!mounted) return;
          Navigator.pop(context, t);
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (!mounted) return;
            Navigator.pop(context);
          },
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final t = _controller.text.trim();
            if (t.isEmpty) return;
            if (!mounted) return;
            Navigator.pop(context, t);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
