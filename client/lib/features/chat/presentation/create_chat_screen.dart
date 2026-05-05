import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Минимальное создание чата: личный (по id пользователя) или группа с названием.
class CreateChatScreen extends StatefulWidget {
  const CreateChatScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  bool _direct = true;
  final _peerIdCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _peerIdCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      if (_direct) {
        final raw = _peerIdCtrl.text.trim();
        final id = int.tryParse(raw);
        if (id == null || id <= 0) {
          setState(() {
            _busy = false;
            _error = 'Укажите числовой id другого пользователя';
          });
          return;
        }
        await widget.apiClient.createDirectChat(id);
      } else {
        final title = _titleCtrl.text.trim();
        if (title.isEmpty) {
          setState(() {
            _busy = false;
            _error = 'Введите название группы';
          });
          return;
        }
        await widget.apiClient.createGroupChat(title);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый чат'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Личный'),
                  icon: Icon(Icons.person_outline),
                ),
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Группа'),
                  icon: Icon(Icons.groups_outlined),
                ),
              ],
              selected: {_direct},
              onSelectionChanged: (s) {
                setState(() => _direct = s.first);
              },
            ),
            const SizedBox(height: 24),
            if (_direct) ...[
              TextField(
                controller: _peerIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID пользователя',
                  hintText: 'Числовой идентификатор',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                enabled: !_busy,
              ),
            ] else ...[
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Название группы',
                  border: OutlineInputBorder(),
                ),
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }
}
