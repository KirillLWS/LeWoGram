import 'package:flutter/material.dart';
import 'package:lewogram_client/core/device/device_fingerprint.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/onboarding/onboarding_prefs.dart';
import 'package:lewogram_client/core/push/push_service.dart';
import 'package:lewogram_client/core/storage/account_storage.dart';
import 'package:lewogram_client/app/app_scope.dart';
/// Регистрация по инвайту: POST /auth/register.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _inviteCtrl = TextEditingController();
  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();

  final _fingerprint = DeviceFingerprint();

  bool _loading = false;
  bool _fpReady = false;
  String? _deviceFingerprint;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFingerprint();
  }

  Future<void> _loadFingerprint() async {
    final fp = await _fingerprint.getOrCreate();
    if (!mounted) return;
    setState(() {
      _deviceFingerprint = fp;
      _fpReady = true;
    });
  }

  @override
  void dispose() {
    _inviteCtrl.dispose();
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final invite = _inviteCtrl.text.trim();
    final login = _loginCtrl.text.trim();
    final password = _passwordCtrl.text;
    final displayName = _displayNameCtrl.text.trim();
    final fp = _deviceFingerprint;

    if (invite.isEmpty || login.isEmpty || password.isEmpty || fp == null) {
      setState(() => _error = 'Заполните инвайт, логин, пароль и дождитесь отпечатка устройства');
      return;
    }
    if (login.length < 3) {
      setState(() => _error = 'Логин не короче 3 символов');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Пароль не короче 8 символов');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final scope = AppScope.of(context);

    try {
      final reg = await scope.apiClient.register(
        inviteToken: invite,
        login: login,
        password: password,
        deviceFingerprint: fp,
        displayName: displayName.isEmpty ? null : displayName,
      );
      if (!mounted) return;

      final phrase = reg['recovery_phrase'] as String?;
      if (phrase != null && phrase.isNotEmpty) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Сохраните фразу восстановления'),
            content: SingleChildScrollView(
              child: SelectableText(phrase),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Я сохранил фразу'),
              ),
            ],
          ),
        );
      }

      final me = await scope.apiClient.getMe();
      await AccountStorage.upsert(me);
      await PushService.initAndGetToken(scope.apiClient);
      if (!mounted) return;
      final onboardingDone = await OnboardingPrefs.isDone();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        onboardingDone ? '/home' : '/onboarding-permissions',
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Регистрация'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Новый аккаунт',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Нужен действующий инвайт-токен.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _inviteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Инвайт-токен',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.vpn_key_outlined),
                        ),
                        autocorrect: false,
                        enabled: !_loading,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _loginCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Логин',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enabled: !_loading,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Пароль',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        onSubmitted: (_) {
                          if (!_loading && _fpReady) _submit();
                        },
                        enabled: !_loading,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _displayNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Отображаемое имя (необязательно)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        textInputAction: TextInputAction.done,
                        enabled: !_loading,
                      ),
                      const SizedBox(height: 16),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Отпечаток устройства',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.fingerprint),
                          alignLabelWithHint: true,
                        ),
                        child: Text(
                          _fpReady && _deviceFingerprint != null
                              ? _deviceFingerprint!
                              : 'Получение…',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed:
                    (_loading || !_fpReady) ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Зарегистрироваться'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Уже есть аккаунт? Войти'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
