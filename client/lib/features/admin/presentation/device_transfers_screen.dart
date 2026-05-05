import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// Админ: очередь и история смены устройств.
class DeviceTransfersScreen extends StatefulWidget {
  const DeviceTransfersScreen({super.key});

  @override
  State<DeviceTransfersScreen> createState() => _DeviceTransfersScreenState();
}

class _DeviceTransfersScreenState extends State<DeviceTransfersScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = AppScope.of(context).apiClient;
    try {
      final m = await api.deviceTransferAdminOverview();
      final p = m['pending'];
      final h = m['history'];
      if (!mounted) return;
      setState(() {
        _pending = (p is List)
            ? p.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
        _history = (h is List)
            ? h.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
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
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openMaps(double? lat, double? lng) async {
    if (lat == null || lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps?q=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _approve(int id, bool revokeOld) async {
    final api = AppScope.of(context).apiClient;
    try {
      await api.deviceTransferApprove(id, revokeOld: revokeOld);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Запрос подтверждён')),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deny(int id) async {
    final noteCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Отказать в доступе'),
          content: TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Причина отказа (обязательно)',
              border: OutlineInputBorder(),
            ),
            maxLines: 4,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (noteCtrl.text.trim().length < 3) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Отказать'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final note = noteCtrl.text.trim();
      if (note.length < 3) return;

      final api = AppScope.of(context).apiClient;
      await api.deviceTransferDeny(id, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Запрос отклонён')),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      noteCtrl.dispose();
    }
  }

  Widget _geoPreview(Map<String, dynamic> r, ThemeData theme) {
    final lat = r['req_geo_lat'];
    final lng = r['req_geo_lng'];
    final la = lat is num ? lat.toDouble() : null;
    final ln = lng is num ? lng.toDouble() : null;
    if (la == null || ln == null) {
      return Text(
        'Геолокация не указана',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 100,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_outlined, color: theme.colorScheme.primary),
                const SizedBox(height: 4),
                Text(
                  '${la.toStringAsFixed(5)}, ${ln.toStringAsFixed(5)}',
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _openMaps(la, ln),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Открыть в картах'),
        ),
      ],
    );
  }

  Widget _card(
    Map<String, dynamic> r, {
    required bool showActions,
    required ThemeData theme,
  }) {
    final id = (r['id'] as num).toInt();
    final login = r['user_login'] as String? ?? '';
    final dn = r['user_display_name'] as String? ?? '';
    final mode = r['mode'] as String? ?? '';
    final status = r['status'] as String? ?? '';
    final reason = r['reason'] as String? ?? '';
    final model = r['req_device_model'] as String? ?? '—';
    final os = r['req_device_os'] as String? ?? '—';
    final fp = r['req_device_fingerprint'] as String? ?? '—';
    final ip = r['req_ip_address'] as String? ?? '—';
    final created = r['created_at'] as String? ?? '—';
    final expires = r['expires_at'] as String? ?? '—';
    final decidedBy = r['decided_by_login'] as String? ?? '';
    final decisionNote = r['decision_note'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    showActions ? 'Заявка #$id' : '$status · #$id',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!showActions)
                  Chip(
                    label: Text(status),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Пользователь: $login${dn.isNotEmpty ? ' · $dn' : ''}'),
            const SizedBox(height: 8),
            Text('Устройство: $model · $os'),
            const SizedBox(height: 4),
            SelectableText('Отпечаток: $fp', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('IP: $ip'),
            const SizedBox(height: 8),
            _geoPreview(r, theme),
            const SizedBox(height: 8),
            Text('Создано: $created'),
            Text('Истекает: $expires'),
            Text(
              mode == 'transfer'
                  ? 'Режим: полная смена устройства'
                  : 'Режим: дополнительное устройство',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text('Причина:', style: theme.textTheme.labelLarge),
            Text(reason),
            if (!showActions && (decidedBy.isNotEmpty || decisionNote.isNotEmpty)) ...[
              const SizedBox(height: 8),
              if (decidedBy.isNotEmpty) Text('Решение от: $decidedBy'),
              if (decisionNote.isNotEmpty) Text('Комментарий: $decisionNote'),
            ],
            if (showActions) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _approve(id, false),
                    child: const Text('Разрешить (доп. устройство)'),
                  ),
                  FilledButton(
                    onPressed: () => _approve(id, true),
                    child: const Text('Разрешить + отозвать старые'),
                  ),
                  OutlinedButton(
                    onPressed: () => _deny(id),
                    child: const Text('Отказать'),
                  ),
                ],
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
        title: const Text('Смена устройства'),
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
                        'Ожидают решения',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_pending.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Text(
                            'Нет активных заявок',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        ..._pending.map(
                          (r) => _card(r, showActions: true, theme: theme),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'История',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_history.isEmpty)
                        Text(
                          'Пока пусто',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        ..._history.map(
                          (r) => _card(r, showActions: false, theme: theme),
                        ),
                    ],
                  ),
                ),
    );
  }
}
