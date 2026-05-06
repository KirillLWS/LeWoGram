import 'package:flutter/material.dart';
import 'package:lewogram_client/core/network/api_client.dart'
    show ApiClient, ApiException, UnauthorizedException;
import 'package:lewogram_client/features/owner/presentation/owner_hidden_moderation_screen.dart';

/// Чаты сервера для владельца (данные из [GET /owner/server-chats]).
class OwnerChatsTab extends StatefulWidget {
  const OwnerChatsTab({
    super.key,
    required this.apiClient,
    this.onJoinAsParticipant,
  });

  final ApiClient apiClient;
  final void Function(String chatId)? onJoinAsParticipant;

  @override
  State<OwnerChatsTab> createState() => _OwnerChatsTabState();
}

class _OwnerChatsTabState extends State<OwnerChatsTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
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
    try {
      final raw = await widget.apiClient.ownerServerChats();
      if (!mounted) return;
      final list = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
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

  String _title(Map<String, dynamic> c) {
    final t = c['title'] as String?;
    if (t != null && t.trim().isNotEmpty) return t.trim();
    final id = c['id'];
    return 'Чат #$id';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.25,
              child: Center(
                child: Text(
                  'Нет чатов',
                  style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final c = _rows[index];
          final id = (c['id'] as num).toInt();
          final title = _title(c);
          final typ = c['type'] as String? ?? '';
          return Material(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: Icon(Icons.forum_outlined, color: cs.primary),
              title: Text(title),
              subtitle: Text(
                '$typ · id=$id',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.shield_outlined),
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => OwnerHiddenModerationScreen(
                      chatId: '$id',
                      chatTitle: title,
                      onJoinAsParticipant: widget.onJoinAsParticipant,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
