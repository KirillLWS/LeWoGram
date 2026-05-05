import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/features/chat/data/chat_models.dart';
import 'package:lewogram_client/features/chat/presentation/chat_avatar.dart';

/// Экран переписки по [chatId]. Сообщения подгружаются через [ApiClient.getMessages],
/// отправка — [ApiClient.sendText].
///
/// [currentUserId] можно передать из списка после [ApiClient.getMe]; если `null`,
/// экран один раз запросит [/auth/me] в [initState].
///
/// Заголовок AppBar: приоритет локального переименования → [initialDisplayTitle] →
/// [initialTitle] → peer → «Чат #id».
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    required this.apiClient,
    this.currentUserId,
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

  final String? initialDisplayTitle;
  final String? initialTitle;

  /// Аватар из списка чатов ([avatar_path]); показывается в AppBar при разрешимом URL.
  final String? initialAvatarPath;
  final String? peerLogin;
  final String? peerDisplayName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  List<MessageItem> _messages = [];
  bool _loading = true;
  String? _error;
  int? _currentUserId;
  Timer? _pollTimer;

  /// После успешного переименования (или ввод пользователя до появления API).
  String? _titleOverride;

  /// Последний message_id, для которого уже ушёл успешный mark-read (не дублировать запросы).
  int? _lastMarkReadSentForMessageId;

  /// Защита от параллельных POST /messages/mark-read.
  bool _markReadInProgress = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = widget.currentUserId;
    _initUserAndMessages();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _loadMessages(silent: true),
    );
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
    await _loadMessages();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
    final ctrl = TextEditingController(text: _appBarTitle);
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Название чата'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Отображаемое имя',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            maxLines: 1,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
    if (submitted != true || !mounted) {
      ctrl.dispose();
      return;
    }
    final next = ctrl.text.trim();
    ctrl.dispose();
    if (next.isEmpty) return;
    try {
      await widget.apiClient.renameChat(widget.chatId, next);
      if (!mounted) return;
      setState(() => _titleOverride = next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Название обновлено')),
      );
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
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Переименовать',
            onPressed: _showRenameDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: () => _loadMessages(),
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
                : ListView.builder(
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
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
                    onPressed: _send,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(14),
                      shape: const CircleBorder(),
                    ),
                    child: const Icon(Icons.send, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
