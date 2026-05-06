import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Журнал аудита ([GET /admin/audit/events]) — chief_admin / owner.
class AuditEventsScreen extends StatefulWidget {
  const AuditEventsScreen({super.key});

  @override
  State<AuditEventsScreen> createState() => _AuditEventsScreenState();
}

class _AuditEventsScreenState extends State<AuditEventsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  final _userIdCtl = TextEditingController();

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
    setState(() {
      _loading = true;
      _error = null;
    });
    final uidRaw = _userIdCtl.text.trim();
    int? userFilter;
    if (uidRaw.isNotEmpty) {
      userFilter = int.tryParse(uidRaw);
      if (userFilter == null) {
        setState(() {
          _error = 'Некорректный user id';
          _loading = false;
        });
        return;
      }
    }
    try {
      final api = AppScope.of(context).apiClient;
      final raw = await api.adminAuditEvents(
        limit: 80,
        offset: 0,
        userId: userFilter,
      );
      if (!mounted) return;
      final list =
          raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _rows = list;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал аудита'),
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
                    decoration: const InputDecoration(
                      labelText: 'Фильтр user_id (необязательно)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
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
                          final uid = r['user_id'];
                          final aid = r['actor_id'];
                          final et = r['event_type']?.toString() ?? '';
                          final ca = r['created_at']?.toString() ?? '';
                          final payload = r['payload'];
                          final payloadStr = payload is Map
                              ? const JsonEncoder.withIndent('  ')
                                  .convert(payload)
                              : payload?.toString() ?? '';
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '#$id · $et',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  Text(
                                    'user_id: $uid · actor_id: $aid',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  if (ca.isNotEmpty)
                                    Text(ca, style: theme.textTheme.bodySmall),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    payloadStr,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
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
