import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Список всех пользователей (без оболочки [Scaffold]) — для вкладки владельца или экрана админа.
class StaffUsersListView extends StatefulWidget {
  const StaffUsersListView({super.key});

  @override
  State<StaffUsersListView> createState() => _StaffUsersListViewState();
}

class _StaffUsersListViewState extends State<StaffUsersListView> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  int _total = 0;
  bool _loading = true;
  String? _error;
  int _offset = 0;
  static const _pageSize = 40;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final api = AppScope.of(context).apiClient;
    if (reset) {
      setState(() {
        _offset = 0;
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loading = true);
    }
    try {
      final q = _searchCtrl.text.trim();
      final data = await api.adminListUsers(
        limit: _pageSize,
        offset: reset ? 0 : _offset,
        query: q.isEmpty ? null : q,
      );
      if (!mounted) return;
      final list = (data['users'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _total = (data['total'] as num?)?.toInt() ?? list.length;
        if (reset) {
          _users = list;
          _offset = list.length;
        } else {
          _users = [..._users, ...list];
          _offset = _users.length;
        }
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Поиск по логину или имени',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(reset: true),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => _load(reset: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _error!,
                style: TextStyle(color: cs.error),
              ),
            ),
          Expanded(
            child: _loading && _users.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _users.length + (_users.length < _total ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      if (index == _users.length) {
                        return Center(
                          child: TextButton(
                            onPressed: _loading ? null : () => _load(reset: false),
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Загрузить ещё'),
                          ),
                        );
                      }
                      final u = _users[index];
                      final id = (u['id'] as num).toInt();
                      final login = u['login']?.toString() ?? '';
                      final dn = u['display_name']?.toString();
                      final st = u['account_status']?.toString() ?? 'active';
                      final blocked = st != 'active';
                      return Material(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: CircleAvatar(child: Text('$id')),
                          title: Text(dn?.isNotEmpty == true ? dn! : login),
                          subtitle: Text(
                            '$login · $st',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          trailing: Icon(
                            blocked ? Icons.block : Icons.check_circle_outline,
                            color: blocked ? cs.error : cs.primary,
                          ),
                          onTap: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => StaffUserDetailScreen(
                                  user: Map<String, dynamic>.from(u),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
    );
  }
}

/// Полноэкранный список пользователей (с [Scaffold]) — из админ-хаба.
class StaffUsersListScreen extends StatelessWidget {
  const StaffUsersListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Пользователи')),
      body: const StaffUsersListView(),
    );
  }
}

class StaffUserDetailScreen extends StatefulWidget {
  const StaffUserDetailScreen({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  State<StaffUserDetailScreen> createState() => _StaffUserDetailScreenState();
}

class _StaffUserDetailScreenState extends State<StaffUserDetailScreen> {
  late Map<String, dynamic> _u;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _u = Map<String, dynamic>.from(widget.user);
  }

  int get _id => (_u['id'] as num).toInt();

  Future<void> _banPermanent() async {
    final reasonCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Постоянная блокировка'),
          content: TextField(
            controller: reasonCtrl,
            decoration: const InputDecoration(
              labelText: 'Причина',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Заблокировать')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _busy = true);
      final row = await AppScope.of(context).apiClient.adminBanUser(
        _id,
        kind: 'permanent',
        reason: reasonCtrl.text.trim(),
      );
      if (mounted) setState(() => _u = Map<String, dynamic>.from(row));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      reasonCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _banTemporary() async {
    final reasonCtrl = TextEditingController();
    int minutes = 60;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Временная блокировка'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Причина',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  Text('Срок: $minutes мин', style: Theme.of(ctx).textTheme.titleSmall),
                  Slider(
                    value: minutes.toDouble(),
                    min: 5,
                    max: 1440,
                    divisions: 100,
                    label: '$minutes мин',
                    onChanged: (v) => setLocal(() => minutes = v.round()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Заблокировать')),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _busy = true);
      final row = await AppScope.of(context).apiClient.adminBanUser(
        _id,
        kind: 'temporary',
        reason: reasonCtrl.text.trim(),
        durationMinutes: minutes,
      );
      if (mounted) setState(() => _u = Map<String, dynamic>.from(row));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      reasonCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unban() async {
    setState(() => _busy = true);
    try {
      final row = await AppScope.of(context).apiClient.adminUnbanUser(_id);
      if (mounted) setState(() => _u = Map<String, dynamic>.from(row));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final login = _u['login']?.toString() ?? '';
    final st = _u['account_status']?.toString() ?? 'active';
    final staffBan = (_u['staff_ban'] as bool?) == true || int.tryParse(_u['staff_ban']?.toString() ?? '0') == 1;

    return Scaffold(
      appBar: AppBar(title: Text(login)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ID: $_id', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Text('Статус: $st${staffBan ? ' (staff)' : ''}'),
                  if ((_u['ban_reason']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Причина: ${_u['ban_reason']}'),
                    ),
                  if (_u['ban_until'] != null && _u['ban_until'].toString().isNotEmpty)
                    Text('До: ${_u['ban_until']}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _banPermanent,
            icon: const Icon(Icons.gavel),
            label: const Text('Заблокировать навсегда'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _banTemporary,
            icon: const Icon(Icons.timer_outlined),
            label: const Text('Временная блокировка'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _unban,
            icon: const Icon(Icons.undo),
            label: const Text('Снять staff-блокировку'),
          ),
        ],
      ),
    );
  }
}
