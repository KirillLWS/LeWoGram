import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Мои заявки на смену устройства (из настроек).
class DeviceTransferMyRequestsScreen extends StatefulWidget {
  const DeviceTransferMyRequestsScreen({super.key});

  @override
  State<DeviceTransferMyRequestsScreen> createState() =>
      _DeviceTransferMyRequestsScreenState();
}

class _DeviceTransferMyRequestsScreenState
    extends State<DeviceTransferMyRequestsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _history = [];
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = AppScope.of(context).apiClient;
    try {
      final raw = await api.deviceTransferMy();
      if (!mounted) return;
      final p = raw['pending'];
      final h = raw['history'];
      final pending = (p is List ? p : const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final history = (h is List ? h : const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _pending = pending;
        _history = history;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on UnauthorizedException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _cancel(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить запрос?'),
        content: const Text(
          'Активная заявка будет снята. При необходимости создайте новую.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final api = AppScope.of(context).apiClient;
    try {
      await api.deviceTransferCancel(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Запрос отменён')),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Widget _card(ThemeData theme, Map<String, dynamic> r, {required bool allowCancel}) {
    final id = (r['id'] as num).toInt();
    final st = r['status'] as String? ?? '';
    final mode = r['mode'] as String? ?? '';
    final reason = r['reason'] as String? ?? '';
    final exp = r['expires_at'] as String? ?? '';
    final pending = st == 'pending';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#$id · $st',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Chip(
                  label: Text(mode),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (exp.isNotEmpty) Text('Истекает: $exp'),
            const SizedBox(height: 8),
            Text(reason),
            if (allowCancel && pending) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _cancel(id),
                child: const Text('Отменить заявку'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои запросы на устройство'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Активные',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_pending.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Нет активных заявок',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        ..._pending.map((r) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _card(theme, r, allowCancel: true),
                            )),
                      Text(
                        'История',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_history.isEmpty)
                        Text(
                          'История пуста',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        ..._history.map((r) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _card(theme, r, allowCancel: false),
                            )),
                    ],
                  ),
                ),
    );
  }
}
