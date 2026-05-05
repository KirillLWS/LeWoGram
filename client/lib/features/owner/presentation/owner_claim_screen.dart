import 'package:flutter/material.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Ввод токена [INITIAL_OWNER_TOKEN] с сервера (одноразовый claim).
class OwnerClaimScreen extends StatefulWidget {
  const OwnerClaimScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<OwnerClaimScreen> createState() => _OwnerClaimScreenState();
}

class _OwnerClaimScreenState extends State<OwnerClaimScreen> {
  final _tokenCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = _tokenCtrl.text.trim();
    if (t.isEmpty) {
      setState(() => _error = 'Введите токен');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await widget.apiClient.claimOwner(t);
      await widget.apiClient.getMe();
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
        title: const Text('Первичный владелец'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Одноразовая активация по токену из переменной окружения сервера INITIAL_OWNER_TOKEN.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _tokenCtrl,
              decoration: const InputDecoration(
                labelText: 'Токен',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              enabled: !_busy,
              autocorrect: false,
            ),
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
                  : const Text('Подтвердить'),
            ),
          ],
        ),
      ),
    );
  }
}
