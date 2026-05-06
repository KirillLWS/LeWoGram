import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Серверные логи входов пользователя (доступно только owner).
class SupportLoginLogsScreen extends StatefulWidget {
  const SupportLoginLogsScreen({super.key});

  @override
  State<SupportLoginLogsScreen> createState() => _SupportLoginLogsScreenState();
}

class _SupportLoginLogsScreenState extends State<SupportLoginLogsScreen> {
  final _userIdCtl = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void dispose() {
    _userIdCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uidRaw = _userIdCtl.text.trim();
    int? userId;
    if (uidRaw.isNotEmpty) {
      userId = int.tryParse(uidRaw);
      if (userId == null || userId <= 0) {
        setState(() {
          _loading = false;
          _error = 'Некорректный user_id';
        });
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = AppScope.of(context).apiClient;
      final raw = await api.ownerSupportLoginLogs(
        limit: 80,
        offset: 0,
        userId: userId,
      );
      if (!mounted) return;
      setState(() {
        _rows = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
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
        _error = '$e';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Серверные логи входов'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userIdCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Фильтр user_id (необязательно)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('Применить'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _rows.isEmpty
                    ? Center(child: Text(_error!, textAlign: TextAlign.center))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final id = (r['id'] as num?)?.toInt() ?? 0;
                          final uid = (r['user_id'] as num?)?.toInt();
                          final login =
                              r['user_login']?.toString() ?? 'unknown';
                          final ok = (r['success'] as num?)?.toInt() == 1;
                          final at = r['logged_in_at']?.toString() ?? '';
                          final fp = r['device_fingerprint']?.toString() ?? '';
                          final ip = r['ip_address']?.toString() ?? '';
                          final dModel =
                              r['last_device_model']?.toString() ?? '';
                          final dOs = r['last_device_os']?.toString() ?? '';
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '#$id · user ${uid ?? '-'} · $login',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: ok
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.error,
                                    ),
                                  ),
                                  Text(
                                    ok ? 'Успешный вход' : 'Неуспешный вход',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  if (at.isNotEmpty)
                                    Text(at, style: theme.textTheme.bodySmall),
                                  const SizedBox(height: 8),
                                  if (ip.isNotEmpty) SelectableText('ip: $ip'),
                                  if (fp.isNotEmpty)
                                    SelectableText('fingerprint: $fp'),
                                  if (dModel.isNotEmpty || dOs.isNotEmpty)
                                    SelectableText(
                                      'device: ${dModel.isNotEmpty ? dModel : '-'}'
                                      ' / ${dOs.isNotEmpty ? dOs : '-'}',
                                    ),
                                ],
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
