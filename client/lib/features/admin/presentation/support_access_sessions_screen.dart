import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Активные сессии согласия на расширенную диагностику (только owner).
class SupportAccessSessionsScreen extends StatefulWidget {
  const SupportAccessSessionsScreen({super.key});

  @override
  State<SupportAccessSessionsScreen> createState() =>
      _SupportAccessSessionsScreenState();
}

class _SupportAccessSessionsScreenState
    extends State<SupportAccessSessionsScreen> {
  final _userIdCtl = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void dispose() {
    _userIdCtl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
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
      final raw = await api.ownerSupportAccessSessions(
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Активные доступы диагностики'),
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
                          final sid = (r['id'] as num?)?.toInt() ?? 0;
                          final uid = (r['user_id'] as num?)?.toInt() ?? 0;
                          final login = r['user_login']?.toString() ?? '';
                          final created = r['created_at']?.toString() ?? '';
                          final expires = r['expires_at']?.toString() ?? '';
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '#$sid · user $uid · $login',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  if (created.isNotEmpty)
                                    Text('Включено: $created',
                                        style: theme.textTheme.bodySmall),
                                  if (expires.isNotEmpty)
                                    Text('Истекает: $expires',
                                        style: theme.textTheme.bodySmall),
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
