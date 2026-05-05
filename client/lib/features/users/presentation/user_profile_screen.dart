import 'package:flutter/material.dart';
import 'package:lewogram_client/core/network/api_client.dart';

import '../data/user_public_profile.dart';

/// Профиль другого пользователя. [onWrite] — создание/открытие директа (координатор).
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.profile,
    required this.apiClient,
    required this.onWrite,
  });

  final UserPublicProfile profile;
  final ApiClient apiClient;

  /// Координатор реализует `POST /messages/chats/direct` и навигацию в чат.
  final Future<void> Function(int otherUserId) onWrite;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _writeBusy = false;
  bool _relationBusy = false;
  String _relation = 'none';
  int? _friendRequestId;

  @override
  void initState() {
    super.initState();
    _relation = widget.profile.relationToMe ?? 'none';
    _friendRequestId = widget.profile.friendRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFriendRelation();
    });
  }

  Future<void> _loadFriendRelation() async {
    try {
      final m = await widget.apiClient.friendsStatus(widget.profile.id);
      if (!mounted) return;
      final rel = m['relation'] as String? ?? 'none';
      int? rid;
      final r = m['request_id'];
      if (r is num) rid = r.toInt();
      setState(() {
        _relation = rel;
        _friendRequestId = rid;
      });
    } on ApiException catch (_) {
      if (!mounted) return;
    } on UnauthorizedException catch (_) {
      if (!mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
  }

  Future<void> _afterRelationAction() async {
    await _loadFriendRelation();
  }

  Future<void> _onWritePressed() async {
    if (_writeBusy) return;
    setState(() => _writeBusy = true);
    try {
      await widget.onWrite(widget.profile.id);
    } finally {
      if (mounted) setState(() => _writeBusy = false);
    }
  }

  Future<void> _onFriendAction(Future<void> Function() fn) async {
    if (_relationBusy) return;
    setState(() => _relationBusy = true);
    try {
      await fn();
      if (!mounted) return;
      await _afterRelationAction();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _relationBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final p = widget.profile;
    final title = p.displayName?.trim().isNotEmpty == true
        ? p.displayName!.trim()
        : p.username;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: CircleAvatar(
                radius: 56,
                backgroundColor: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  size: 64,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              p.displayName?.trim().isNotEmpty == true
                  ? p.displayName!.trim()
                  : p.username,
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '@${p.username}',
              style: textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (p.about != null && p.about!.trim().isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                p.about!.trim(),
                style: textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Статус: ${_relationLabel(_relation)}',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _writeBusy ? null : _onWritePressed,
              child: _writeBusy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Написать'),
            ),
            const SizedBox(height: 12),
            ..._relationButtons(context),
          ],
        ),
      ),
    );
  }

  String _relationLabel(String r) {
    switch (r) {
      case 'none':
        return 'нет связи';
      case 'pending_outgoing':
        return 'заявка отправлена';
      case 'pending_incoming':
        return 'входящая заявка';
      case 'friends':
        return 'друзья';
      case 'blocked_by_me':
        return 'заблокирован вами';
      case 'blocked_me':
        return 'вы заблокированы';
      default:
        return r;
    }
  }

  List<Widget> _relationButtons(BuildContext context) {
    if (_relationBusy) {
      return [
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ];
    }
    switch (_relation) {
      case 'none':
        return [
          OutlinedButton(
            onPressed: _relationBusy
                ? null
                : () => _onFriendAction(
                      () => widget.apiClient.friendsRequest(widget.profile.id),
                    ),
            child: const Text('Добавить в друзья'),
          ),
        ];
      case 'pending_outgoing':
        return [
          OutlinedButton(
            onPressed: _relationBusy
                ? null
                : () => _onFriendAction(
                      () => widget.apiClient.friendsCancel(widget.profile.id),
                    ),
            child: const Text('Отозвать заявку'),
          ),
        ];
      case 'pending_incoming':
        final rid = _friendRequestId;
        if (rid == null) {
          return [
            const Text(
              'Нет id заявки — обновите экран',
              textAlign: TextAlign.center,
            ),
          ];
        }
        return [
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _relationBusy
                      ? null
                      : () => _onFriendAction(() => widget.apiClient.friendsAccept(rid)),
                  child: const Text('Принять'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _relationBusy
                      ? null
                      : () => _onFriendAction(() => widget.apiClient.friendsDecline(rid)),
                  child: const Text('Отклонить'),
                ),
              ),
            ],
          ),
        ];
      case 'friends':
        return [
          OutlinedButton(
            onPressed: _relationBusy
                ? null
                : () => _onFriendAction(
                      () => widget.apiClient.friendsRemove(widget.profile.id),
                    ),
            child: const Text('Удалить из друзей'),
          ),
        ];
      case 'blocked_by_me':
        return [
          OutlinedButton(
            onPressed: _relationBusy
                ? null
                : () => _onFriendAction(
                      () => widget.apiClient.friendsUnblock(widget.profile.id),
                    ),
            child: const Text('Разблокировать'),
          ),
        ];
      case 'blocked_me':
        return [
          const FilledButton.tonal(
            onPressed: null,
            child: Text('Вы заблокированы'),
          ),
        ];
      default:
        return [];
    }
  }
}
