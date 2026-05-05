import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/storage/account_storage.dart';
import 'package:lewogram_client/features/owner/presentation/owner_user_live_geo_screen.dart';

/// Список всех пользователей (без оболочки [Scaffold]) — для вкладки владельца или экрана админа.
class StaffUsersListView extends StatefulWidget {
  const StaffUsersListView({
    super.key,
    this.autoRefreshInterval,
    this.showManualRefreshButton = true,
  });

  /// Если задан — периодический [reset] списка (например только для вкладки owner).
  final Duration? autoRefreshInterval;

  /// Кнопка обновления в строке поиска (у owner отключаем — остаётся автообновление).
  final bool showManualRefreshButton;

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
  bool _initialized = false;
  Timer? _autoTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final d = widget.autoRefreshInterval;
    if (d != null) {
      _autoTimer = Timer.periodic(d, (_) {
        if (!mounted) return;
        _load(reset: true);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load(reset: true);
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
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
                if (widget.showManualRefreshButton) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () => _load(reset: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
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
  List<String> _roles = [];
  bool _rolesLoading = false;
  String? _rolesError;
  List<String> _actorRoles = [];

  static const List<String> _assignableRoles = [
    'user',
    'developer',
    'admin',
    'chief_admin',
    'owner',
  ];

  static const _mutateRoles = {'owner', 'chief_admin', 'admin'};

  static int _roleRank(String role) {
    switch (role.trim().toLowerCase()) {
      case 'user':
        return 0;
      case 'developer':
        return 1;
      case 'admin':
        return 2;
      case 'chief_admin':
        return 3;
      case 'owner':
        return 4;
      default:
        return -1;
    }
  }

  static int _highestRank(Iterable<String> roles) {
    var m = 0;
    for (final r in roles) {
      final k = _roleRank(r);
      if (k > m) m = k;
    }
    return m;
  }

  bool get _actorIsOwner =>
      _actorRoles.map((e) => e.toLowerCase()).contains('owner');

  bool _actorMayMutateRoles() {
    final s = _actorRoles.map((e) => e.toLowerCase()).toSet();
    return s.intersection(_mutateRoles).isNotEmpty;
  }

  /// Как в admin roles_service: только роль строго ниже вашей; владелец — любая.
  bool _canGrantRole(String role) {
    final r = role.trim().toLowerCase();
    if (!_actorMayMutateRoles()) return false;
    if (_actorIsOwner) return true;
    return _roleRank(r) < _highestRank(_actorRoles);
  }

  /// Как в admin roles_service: chief_admin/owner снимает только владелец; иначе только ниже вашей.
  bool _canRevokeRole(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'owner') return _actorIsOwner;
    if (r == 'chief_admin') return _actorIsOwner;
    if (!_actorMayMutateRoles()) return false;
    if (_actorIsOwner) return true;
    return _roleRank(r) < _highestRank(_actorRoles);
  }

  String get _grantRestrictionHint =>
      'Назначать можно только роль строго ниже вашей (владелец может все).';

  String get _revokeRestrictionHint =>
      'Снять эту роль может пользователь с более высоким уровнем.';

  @override
  void initState() {
    super.initState();
    _u = Map<String, dynamic>.from(widget.user);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadActorRoles();
      _loadRoles();
    });
  }

  Future<void> _loadActorRoles() async {
    List<String> roles = [];
    final cached = await AccountStorage.read();
    final raw = cached?['roles'];
    if (raw is List<dynamic>) {
      roles = raw.map((e) => e.toString()).toList();
    }
    if (roles.isEmpty && mounted) {
      try {
        final me = await AppScope.of(context).apiClient.getMe();
        final list = me['roles'];
        if (list is List<dynamic>) {
          roles = list.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _actorRoles = roles);
  }

  int get _id => (_u['id'] as num).toInt();

  Future<void> _loadRoles() async {
    setState(() {
      _rolesLoading = true;
      _rolesError = null;
    });
    try {
      final m = await AppScope.of(context).apiClient.adminGetUserRoles(_id);
      final list =
          (m['roles'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      if (!mounted) return;
      setState(() {
        _roles = list;
        _rolesLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _rolesError = e.message;
        _rolesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rolesError = '$e';
        _rolesLoading = false;
      });
    }
  }

  Future<void> _grantRole(String role) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).apiClient.adminGrantUserRole(_id, role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Роль назначена: $role')),
      );
      await _loadRoles();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeRole(String role) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).apiClient.adminRevokeUserRole(_id, role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Роль снята: $role')),
      );
      await _loadRoles();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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

  Future<void> _revokeAllSessions() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить все сессии'),
        content: const Text(
          'Пользователь будет разлогинен на всех устройствах.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сбросить')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await AppScope.of(context).apiClient.adminRevokeUserSessions(_id);
      if (!mounted) return;
      final n = r['revoked'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сессий отозвано: $n')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _targetRoleChip(String r) {
    final canDel = _canRevokeRole(r);
    final chip = InputChip(
      label: Text(r),
      onDeleted: (_busy || !canDel) ? null : () => _revokeRole(r),
    );
    if (canDel) return chip;
    return Tooltip(
      message: _revokeRestrictionHint,
      child: chip,
    );
  }

  Widget _grantRoleChip(String r) {
    final ok = _canGrantRole(r);
    final chip = ActionChip(
      label: Text(r),
      onPressed: (_busy || !ok) ? null : () => _grantRole(r),
    );
    if (ok) return chip;
    return Tooltip(
      message: _grantRestrictionHint,
      child: chip,
    );
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
                  if ((_u['created_at']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Регистрация: ${_u['created_at']}',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  if ((_u['last_seen_at']?.toString() ?? '').isNotEmpty)
                    Text(
                      'Последняя активность: ${_u['last_seen_at']}',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Роли RBAC', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (_rolesLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(minHeight: 2),
                    )
                  else if (_rolesError != null)
                    Text(_rolesError!, style: TextStyle(color: cs.error))
                  else if (_roles.isEmpty)
                    Text('Роли не загружены', style: theme.textTheme.bodySmall)
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _roles.map(_targetRoleChip).toList(),
                    ),
                  const SizedBox(height: 12),
                  Text('Назначить / понизить (одна основная роль)', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    _grantRestrictionHint,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _assignableRoles.map(_grantRoleChip).toList(),
                  ),
                ],
              ),
            ),
          ),
          if (_actorIsOwner) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => OwnerUserLiveGeoScreen(
                      apiClient: AppScope.of(context).apiClient,
                      userId: _id,
                      displayLabel: login,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.my_location_outlined),
              label: const Text('Лайв-геолокация'),
            ),
          ],
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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _revokeAllSessions,
            icon: const Icon(Icons.logout),
            label: const Text('Сбросить все сессии'),
          ),
        ],
      ),
    );
  }
}
