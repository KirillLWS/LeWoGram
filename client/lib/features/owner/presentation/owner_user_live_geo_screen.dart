import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// Лайв-геолокация пользователя для владельца.
/// Опрашивает /owner/users/{id}/live-geo каждые 5 секунд, показывает последнюю точку
/// и историю; предоставляет ссылку на карту OpenStreetMap.
class OwnerUserLiveGeoScreen extends StatefulWidget {
  const OwnerUserLiveGeoScreen({
    super.key,
    required this.apiClient,
    required this.userId,
    required this.displayLabel,
  });

  final ApiClient apiClient;
  final int userId;
  final String displayLabel;

  @override
  State<OwnerUserLiveGeoScreen> createState() => _OwnerUserLiveGeoScreenState();
}

class _OwnerUserLiveGeoScreenState extends State<OwnerUserLiveGeoScreen> {
  Timer? _poller;
  List<Map<String, dynamic>> _points = [];
  Map<String, dynamic>? _latest;
  bool _loading = true;
  String? _error;
  bool _autoRefresh = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poller = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (_autoRefresh && mounted) _refresh(silent: true);
      },
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await widget.apiClient.ownerUserLiveGeo(widget.userId);
      if (!mounted) return;
      final list = (data['data'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final latest = data['latest'];
      setState(() {
        _points = list;
        _latest = latest is Map ? Map<String, dynamic>.from(latest) : null;
        _loading = false;
        _error = null;
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

  Uri _osmUrl(double lat, double lng) => Uri.parse(
        'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng',
      );

  Future<void> _openOnMap(double lat, double lng) async {
    final uri = _osmUrl(lat, lng);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: '$lat, $lng'));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Координаты скопированы в буфер')),
      );
    }
  }

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final l = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  Widget _latestCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = _latest;
    if (l == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Точек пока нет — пользователь не разрешил лайв-гео или не отправлял.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final lat = (l['lat'] as num).toDouble();
    final lng = (l['lng'] as num).toDouble();
    final acc = (l['accuracy_m'] as num?)?.toDouble();
    final at = _formatTime(l['recorded_at']?.toString() ?? '');
    return Card(
      color: cs.primaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Последняя точка', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SelectableText(
              '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
              style: theme.textTheme.titleMedium,
            ),
            if (acc != null)
              Text('точность: ±${acc.toStringAsFixed(0)} м',
                  style: theme.textTheme.bodySmall),
            Text('обновлено: $at', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => _openOnMap(lat, lng),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Открыть на карте'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: '$lat, $lng'));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скопировано')),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Скопировать'),
                ),
              ],
            ),
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.displayLabel),
            Text(
              'Лайв-геолокация',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _autoRefresh ? 'Авто-обновление: вкл' : 'Авто-обновление: выкл',
            icon: Icon(_autoRefresh ? Icons.sync : Icons.sync_disabled),
            onPressed: () => setState(() => _autoRefresh = !_autoRefresh),
          ),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(),
        child: _loading && _points.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _points.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      Center(child: Text(_error!)),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _latestCard(context),
                      const SizedBox(height: 12),
                      Text(
                        'История (${_points.length})',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ..._points.map((p) {
                        final lat = (p['lat'] as num).toDouble();
                        final lng = (p['lng'] as num).toDouble();
                        final acc = (p['accuracy_m'] as num?)?.toDouble();
                        final at = _formatTime(
                            p['recorded_at']?.toString() ?? '');
                        return Card(
                          child: ListTile(
                            dense: true,
                            title: Text(
                              '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                            ),
                            subtitle: Text(
                              acc != null
                                  ? '$at · ±${acc.toStringAsFixed(0)} м'
                                  : at,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.map_outlined),
                              onPressed: () => _openOnMap(lat, lng),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
      ),
    );
  }
}
