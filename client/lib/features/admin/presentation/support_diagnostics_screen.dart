import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/features/admin/presentation/log_entry_tile.dart';

/// Журнал диагностики пользователей ([GET /admin/support/diagnostics]).
class SupportDiagnosticsScreen extends StatefulWidget {
  const SupportDiagnosticsScreen({super.key});

  @override
  State<SupportDiagnosticsScreen> createState() =>
      _SupportDiagnosticsScreenState();
}

class _SupportDiagnosticsScreenState extends State<SupportDiagnosticsScreen> {
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
          _error = 'Некорректный user_id';
          _loading = false;
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
      final raw = await api.adminSupportDiagnostics(
        limit: 80,
        offset: 0,
        userId: userId,
      );
      if (!mounted) return;
      final list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
        title: const Text('Журнал диагностики'),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
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
                          final uid = (r['user_id'] as num?)?.toInt() ?? 0;
                          final login = r['user_login']?.toString() ?? '';
                          final body = r['body']?.toString() ?? '';
                          final meta = r['client_meta']?.toString();
                          final ca = r['created_at']?.toString() ?? '';
                          final hasMeta = meta != null && meta.trim().isNotEmpty;
                          final details = <String, Object?>{
                            if (body.isNotEmpty) 'body': body,
                            if (hasMeta) 'client_meta': meta,
                          };
                          return LogEntryTile(
                            title: '#$id · user $uid · $login',
                            subtitle: ca,
                            summary: LogEntryTile.detailsToOneLine(body),
                            details: details.isEmpty ? null : details,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
