import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/device/support_telemetry.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/features/chat/presentation/chat_screen.dart';

/// Список моих тикетов поддержки + создание нового.
/// Открывается из «Настройки → Связь с поддержкой».
class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  List<Map<String, dynamic>> _tickets = [];
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
      final raw = await api.listMySupportTickets();
      if (!mounted) return;
      setState(() {
        _tickets = raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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

  Future<void> _createTicket() async {
    final subjCtl = TextEditingController();
    final descCtl = TextEditingController();
    bool attachDiag = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Новый запрос в поддержку'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: subjCtl,
                  autofocus: true,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Тема',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtl,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'Описание проблемы (необязательно)',
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: attachDiag,
                  onChanged: (v) => setSt(() => attachDiag = v ?? false),
                  title: const Text('Прикрепить диагностику клиента'),
                  subtitle: const Text(
                    'Версия приложения, ОС, локаль и т.п. помогут быстрее решить проблему.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
    final subject = subjCtl.text.trim();
    final desc = descCtl.text.trim();
    subjCtl.dispose();
    descCtl.dispose();
    if (ok != true || !mounted) return;

    String? clientMeta;
    if (attachDiag) {
      try {
        final snap = await collectSupportTelemetrySnapshot();
        clientMeta = jsonEncode(snap);
      } catch (_) {
        clientMeta = null;
      }
    }

    try {
      final api = AppScope.of(context).apiClient;
      final t = await api.createSupportTicket(
        subject: subject.isEmpty ? null : subject,
        diagnosticBody: desc.isEmpty ? null : desc,
        clientMeta: clientMeta,
      );
      if (!mounted) return;
      await _openTicket(t);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openTicket(Map<String, dynamic> t) async {
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

  Color _statusColor(BuildContext context, String? s) {
    final cs = Theme.of(context).colorScheme;
    switch ((s ?? 'open').toLowerCase()) {
      case 'closed_finalized':
        return cs.onSurfaceVariant;
      case 'both_closed':
        return cs.tertiary;
      case 'user_closed':
      case 'admin_closed':
        return cs.secondary;
      default:
        return cs.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Связь с поддержкой'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTicket,
        icon: const Icon(Icons.add),
        label: const Text('Новый запрос'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _tickets.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _tickets.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      Center(child: Text(_error!)),
                    ],
                  )
                : _tickets.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 80),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Активных запросов нет.\n'
                                'Нажмите «Новый запрос», чтобы написать в поддержку.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _tickets.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final t = _tickets[i];
                          final id = (t['id'] as num).toInt();
                          final title = t['title']?.toString() ??
                              'Запрос #$id';
                          final st = t['support_status']?.toString();
                          final ca = t['updated_at']?.toString() ??
                              t['created_at']?.toString() ??
                              '';
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.support_agent),
                              title: Text(title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _statusLabel(st),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: _statusColor(context, st),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (ca.isNotEmpty)
                                    Text(
                                      ca,
                                      style: theme.textTheme.labelSmall,
                                    ),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openTicket(t),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
