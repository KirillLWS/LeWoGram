import 'package:flutter/material.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/refresh/auto_refresh_mixin.dart';
import 'package:lewogram_client/features/chat/presentation/chat_avatar.dart';
import 'package:lewogram_client/features/chat/presentation/chat_screen.dart';

/// Вкладка «Друзья»: списки, заявки, подписки.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    super.key,
    required this.apiClient,
    required this.incomingBadgeNotifier,
  });

  final ApiClient apiClient;
  final ValueNotifier<int> incomingBadgeNotifier;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Друзья'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Друзья'),
              Tab(text: 'Заявки'),
              Tab(text: 'Подписки'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _FriendsListTab(
              apiClient: widget.apiClient,
            ),
            _IncomingRequestsTab(
              apiClient: widget.apiClient,
              incomingBadgeNotifier: widget.incomingBadgeNotifier,
            ),
            _OutgoingRequestsTab(
              apiClient: widget.apiClient,
            ),
          ],
        ),
      ),
    );
  }
}

String _friendTitle(Map<String, dynamic> u) {
  final dn = u['display_name'] as String?;
  if (dn != null && dn.trim().isNotEmpty) return dn.trim();
  final un = u['username'] as String?;
  if (un != null && un.trim().isNotEmpty) return un.trim();
  return 'Пользователь #${u['id']}';
}

class _FriendsListTab extends StatefulWidget {
  const _FriendsListTab({required this.apiClient});

  final ApiClient apiClient;

  @override
  State<_FriendsListTab> createState() => _FriendsListTabState();
}

class _FriendsListTabState extends State<_FriendsListTab> with AutoRefreshMixin {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  Duration get refreshInterval => const Duration(seconds: 30);

  @override
  Future<void> performRefresh() => _load(silent: true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = await widget.apiClient.friendsList();
      if (!mounted) return;
      setState(() {
        _rows = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  Future<void> _openChat(int otherId, String titleHint) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final chat = await widget.apiClient.createDirectChat(otherId);
      if (!context.mounted) return;
      final chatId = (chat['id'] as num).toInt();
      await nav.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            chatId: chatId,
            apiClient: widget.apiClient,
            initialDisplayTitle: titleHint,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: TextStyle(color: cs.error)),
        ),
      );
    }
    if (_rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.25,
              child: Center(
                child: Text(
                  'Нет друзей',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, i) {
          final u = _rows[i];
          final title = _friendTitle(u);
          final avatar = u['avatar_path'] as String?;
          return ListTile(
            leading: ChatAvatarCircle(
              letter: chatAvatarLetter(title),
              avatarPath: avatar,
            ),
            title: Text(title),
            subtitle: Text('@${u['username'] ?? ''}'),
            trailing: FilledButton.tonal(
              onPressed: () => _openChat((u['id'] as num).toInt(), title),
              child: const Text('Открыть чат'),
            ),
          );
        },
      ),
    );
  }
}

class _IncomingRequestsTab extends StatefulWidget {
  const _IncomingRequestsTab({
    required this.apiClient,
    required this.incomingBadgeNotifier,
  });

  final ApiClient apiClient;
  final ValueNotifier<int> incomingBadgeNotifier;

  @override
  State<_IncomingRequestsTab> createState() => _IncomingRequestsTabState();
}

class _IncomingRequestsTabState extends State<_IncomingRequestsTab> with AutoRefreshMixin {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  Duration get refreshInterval => const Duration(seconds: 30);

  @override
  Future<void> performRefresh() => _load(silent: true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _syncBadge() {
    widget.incomingBadgeNotifier.value = _rows.length;
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = await widget.apiClient.friendsIncoming();
      if (!mounted) return;
      setState(() {
        _rows = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
      _syncBadge();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
      _syncBadge();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.toString();
      });
      _syncBadge();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: TextStyle(color: cs.error)),
        ),
      );
    }
    if (_rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.25,
              child: Center(
                child: Text(
                  'Нет входящих заявок',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final m = _rows[i];
          final reqId = (m['request_id'] as num).toInt();
          final u = Map<String, dynamic>.from(m['user'] as Map);
          final title = _friendTitle(u);
          final avatar = u['avatar_path'] as String?;
          return ListTile(
            leading: ChatAvatarCircle(
              letter: chatAvatarLetter(title),
              avatarPath: avatar,
            ),
            title: Text(title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@${u['username'] ?? ''}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await widget.apiClient.friendsAccept(reqId);
                            if (!context.mounted) return;
                            await _load();
                          } on ApiException catch (e) {
                            if (!context.mounted) return;
                            messenger.showSnackBar(
                              SnackBar(content: Text(e.message)),
                            );
                          }
                        },
                        child: const Text('Принять'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await widget.apiClient.friendsDecline(reqId);
                            if (!context.mounted) return;
                            await _load();
                          } on ApiException catch (e) {
                            if (!context.mounted) return;
                            messenger.showSnackBar(
                              SnackBar(content: Text(e.message)),
                            );
                          }
                        },
                        child: const Text('Отклонить'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            isThreeLine: true,
          );
        },
      ),
    );
  }
}

class _OutgoingRequestsTab extends StatefulWidget {
  const _OutgoingRequestsTab({required this.apiClient});

  final ApiClient apiClient;

  @override
  State<_OutgoingRequestsTab> createState() => _OutgoingRequestsTabState();
}

class _OutgoingRequestsTabState extends State<_OutgoingRequestsTab> with AutoRefreshMixin {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  Duration get refreshInterval => const Duration(seconds: 30);

  @override
  Future<void> performRefresh() => _load(silent: true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = await widget.apiClient.friendsOutgoing();
      if (!mounted) return;
      setState(() {
        _rows = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: TextStyle(color: cs.error)),
        ),
      );
    }
    if (_rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.25,
              child: Center(
                child: Text(
                  'Нет исходящих заявок',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final m = _rows[i];
          final u = Map<String, dynamic>.from(m['user'] as Map);
          final targetId = (u['id'] as num).toInt();
          final title = _friendTitle(u);
          final avatar = u['avatar_path'] as String?;
          return ListTile(
            leading: ChatAvatarCircle(
              letter: chatAvatarLetter(title),
              avatarPath: avatar,
            ),
            title: Text(title),
            subtitle: Text('@${u['username'] ?? ''}'),
            trailing: OutlinedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await widget.apiClient.friendsCancel(targetId);
                  if (!context.mounted) return;
                  await _load();
                } on ApiException catch (e) {
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text(e.message)),
                  );
                }
              },
              child: const Text('Отозвать'),
            ),
          );
        },
      ),
    );
  }
}
