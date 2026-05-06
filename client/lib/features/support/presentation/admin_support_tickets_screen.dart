import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/features/chat/presentation/chat_screen.dart';

/// Папка «Поддержка» для admin / chief_admin / owner.
/// Группирует тикеты по пользователю; раскрытие — список под-чатов.
class AdminSupportTicketsScreen extends StatefulWidget {
  const AdminSupportTicketsScreen({super.key});

  @override
  State<AdminSupportTicketsScreen> createState() =>
      _AdminSupportTicketsScreenState();
}

class _AdminSupportTicketsScreenState
    extends State<AdminSupportTicketsScreen> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = AppScope.of(context).apiClient;
      final raw = await api.listAllSupportTickets();
      if (!mounted) return;
      setState(() {
        _all = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _statusLabel(String? s) {
    switch ((s ?? 'open').toLowerCase()) {
      case 'open':
        return 'Открыт';
      case 'user_closed':
        return 'Закрыт пользователем';
      case 'admin_closed':
        return 'Закрыт поддержкой';
      case 'both_closed':
        return 'Закрыт обеими сторонами';
      case 'closed_finalized':
        return 'Окончательно закрыт';
      default:
        return s ?? '';
    }
  }

  Future<void> _open(Map<String, dynamic> t) async {
    final id = (t['id'] as num).toInt();
    final title = t['title']?.toString() ?? 'Запрос #$id';
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          chatId: id,
          apiClient: AppScope.of(context).apiClient,
          chatType: 'support_ticket',
          initialTitle: title,
          allowSupportStaffReply: true,
        ),
      ),
    );
    if (mounted) _load();
  }

  Map<int, List<Map<String, dynamic>>> _groupByUser() {
    final out = <int, List<Map<String, dynamic>>>{};
    for (final t in _all) {
      final uid = (t['support_user_id'] as num?)?.toInt() ?? 0;
      out.putIfAbsent(uid, () => []).add(t);
    }
    return out;
  }

  String _userLabel(int uid, Map<String, dynamic> sample) {
    final dn = sample['user_display_name']?.toString();
    final ln = sample['user_login']?.toString();
    if (dn != null && dn.isNotEmpty) return '$dn (id=$uid)';
    if (ln != null && ln.isNotEmpty) return '$ln (id=$uid)';
    return 'user $uid';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final groups = _groupByUser();
    final keys = groups.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Поддержка'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _all.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _all.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      Center(child: Text(_error!)),
                    ],
                  )
                : _all.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 80),
                          Center(child: Text('Тикетов нет')),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.all(8),
                        children: keys.map((uid) {
                          final tickets = groups[uid]!;
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: ExpansionTile(
                              leading: const Icon(Icons.person_outline),
                              title: Text(_userLabel(uid, tickets.first)),
                              subtitle: Text(
                                '${tickets.length} тикет(ов)',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              children: tickets.map((t) {
                                final id = (t['id'] as num).toInt();
                                final title = t['title']?.toString() ??
                                    'Запрос #$id';
                                final st =
                                    t['support_status']?.toString() ?? 'open';
                                final ca = t['updated_at']?.toString() ??
                                    t['created_at']?.toString() ??
                                    '';
                                return ListTile(
                                  leading: const Icon(Icons.support_agent),
                                  title: Text(title),
                                  subtitle: Text('$ca · ${_statusLabel(st)}'),
                                  trailing:
                                      const Icon(Icons.chevron_right),
                                  onTap: () => _open(t),
                                );
                              }).toList(),
                            ),
                          );
                        }).toList(),
                      ),
      ),
    );
  }
}
