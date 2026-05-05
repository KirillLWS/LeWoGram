import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lewogram_client/core/refresh/auto_refresh_mixin.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Управление инвайтами (роли owner / chief_admin / admin на backend).
class InvitesScreen extends StatefulWidget {
  const InvitesScreen({
    super.key,
    required this.apiClient,
  });

  final ApiClient apiClient;

  @override
  State<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends State<InvitesScreen> with AutoRefreshMixin {
  final _hoursCtrl = TextEditingController(text: '48');
  final _noteCtrl = TextEditingController();

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _creating = false;
  String? _error;
  String? _lastCreatedToken;

  @override
  Duration get refreshInterval => const Duration(seconds: 30);

  @override
  Future<void> performRefresh() => _refresh(silent: true);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = await widget.apiClient.listAdminInvites(limit: 100);
      if (!mounted) return;
      setState(() {
        _rows = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.toString();
      });
    }
  }

  Future<void> _create() async {
    final h = int.tryParse(_hoursCtrl.text.trim()) ?? 48;
    if (h < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите корректное число часов')),
      );
      return;
    }
    setState(() {
      _creating = true;
      _lastCreatedToken = null;
    });
    try {
      final map = await widget.apiClient.createAdminInvite(
        expiresHours: h,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      final token = map['token'] as String?;
      setState(() {
        _creating = false;
        _lastCreatedToken = token;
      });
      await _refresh();
      if (!mounted) return;
      if (token != null) {
        await _showTokenDialog(token);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showTokenDialog(String token) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Инвайт создан'),
        content: SelectableText(token),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: token));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Токен скопирован в буфер')),
                );
              }
            },
            child: const Text('Копировать'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static String _statusRu(Map<String, dynamic> row) {
    final used = row['used_at'];
    if (used != null && '$used'.trim().isNotEmpty) return 'Использован';
    final exp = row['expires_at']?.toString();
    if (exp != null && exp.isNotEmpty) {
      final dt = DateTime.tryParse(exp.replaceAll(' ', 'T'));
      if (dt != null && DateTime.now().isAfter(dt.toUtc())) {
        return 'Истёк';
      }
    }
    final active = row['is_active'];
    if (active == false || active == 0) return 'Неактивен';
    return 'Активен';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Инвайты'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    'Создать инвайт',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Новый пользователь сможет зарегистрироваться с этим токеном (как при обычной регистрации).',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _hoursCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Срок действия (часы)',
                      border: OutlineInputBorder(),
                      helperText: 'По умолчанию 48',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Заметка (необязательно)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _creating ? null : _create,
                    icon: _creating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_link),
                    label: Text(_creating ? 'Создание…' : 'Создать invite'),
                  ),
                  if (_lastCreatedToken != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _showTokenDialog(_lastCreatedToken!),
                      icon: const Icon(Icons.copy),
                      label: const Text('Показать последний токен'),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    'Последние инвайты',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: cs.error),
                      ),
                    ),
                ]),
              ),
            ),
            if (_loading && _rows.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_rows.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'Пока нет записей',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final row = _rows[index];
                      final token = row['token'] as String? ?? '';
                      final status = _statusRu(row);
                      final note = row['note'] as String?;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Chip(
                                    label: Text(status),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    tooltip: 'Копировать токен',
                                    icon: const Icon(Icons.copy, size: 20),
                                    onPressed: token.isEmpty
                                        ? null
                                        : () async {
                                            await Clipboard.setData(
                                              ClipboardData(text: token),
                                            );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Токен скопирован'),
                                                ),
                                              );
                                            }
                                          },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                token,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                              if (note != null && note.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  note,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                'До: ${row['expires_at'] ?? '—'}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: _rows.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
