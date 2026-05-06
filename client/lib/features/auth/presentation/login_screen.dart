import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/device/device_fingerprint.dart';
import 'package:lewogram_client/core/network/account_banned_exception.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/onboarding/onboarding_prefs.dart';
import 'package:lewogram_client/core/push/push_service.dart';
import 'package:lewogram_client/core/storage/account_storage.dart';
import 'package:lewogram_client/core/storage/saved_accounts_storage.dart';
import 'package:lewogram_client/features/auth/presentation/account_banned_dialog.dart';

/// Экран входа: логин/пароль, индикатор загрузки, текст ошибки.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _deviceModel = 'Flutter';
  static const String _deviceOs = 'Android';

  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _fingerprint = DeviceFingerprint();
  final SavedAccountsStorage _savedStorage = SavedAccountsStorage();

  bool _loading = false;
  bool _fpReady = false;
  String? _deviceFingerprint;
  String? _error;
  bool _rememberMe = false;
  List<SavedAccountRow> _saved = [];

  @override
  void initState() {
    super.initState();
    _loadFingerprint();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshSavedList();
    });
  }

  Future<void> _refreshSavedList() async {
    final rows = await _savedStorage.listRows();
    if (!mounted) return;
    setState(() => _saved = rows);
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
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _maybePersistSession(String login, Map<String, dynamic> me) async {
    if (!_rememberMe) return;
    final ts = AppScope.of(context).tokenStorage;
    final access = await ts.readToken();
    final refresh = await ts.readRefreshToken();
    if (access == null ||
        refresh == null ||
        access.isEmpty ||
        refresh.isEmpty) {
      return;
    }
    final dn = me['display_name']?.toString().trim();
    final un = me['username']?.toString().trim();
    final label = (dn != null && dn.isNotEmpty)
        ? dn
        : ((un != null && un.isNotEmpty) ? un : login);
    await _savedStorage.saveCurrentSession(
      login: login,
      accessToken: access,
      refreshToken: refresh,
      displayLabel: label,
    );
    await _refreshSavedList();
  }

  Future<void> _quickLogin(SavedAccountRow row) async {
    final fp = _deviceFingerprint;
    if (fp == null || !_fpReady) {
      setState(() => _error = 'Подождите инициализации устройства');
      return;
    }
    final tokens = await _savedStorage.readTokens(row.login);
    if (tokens == null) {
      setState(() => _error = 'Нет сохранённых токенов для этого логина');
      return;
    }

    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final api = AppScope.of(context).apiClient;
    final ts = AppScope.of(context).tokenStorage;

    try {
      await ts.saveToken(tokens.access);
      await ts.saveRefreshToken(tokens.refresh);
      final me = await api.getMe();
      await AccountStorage.upsert(me);
      await PushService.initAndGetToken(api);
      if (!mounted) return;
      final onboardingDone = await OnboardingPrefs.isDone();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        onboardingDone ? '/home' : '/onboarding-permissions',
      );
    } on AccountBannedException catch (e) {
      if (!mounted) return;
      await showAccountBannedDialog(context, e);
    } on UnauthorizedException catch (_) {
      await ts.clearToken();
      await _savedStorage.remove(row.login);
      await _refreshSavedList();
      if (mounted) {
        setState(() => _error = 'Сессия устарела — войдите паролем');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSavedAccountsManager() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Сохранённые на устройстве',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                if (_saved.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Список пуст'),
                  )
                else
                  ..._saved.map(
                    (r) => ListTile(
                      title: Text(r.label ?? r.login),
                      subtitle: Text(r.login),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _savedStorage.remove(r.login);
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _refreshSavedList();
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    final login = _loginCtrl.text.trim();
    final password = _passwordCtrl.text;
    final fp = _deviceFingerprint;

    if (login.isEmpty || password.isEmpty) {
      setState(() => _error = 'Введите логин и пароль');
      return;
    }
    if (fp == null || !_fpReady) {
      setState(() => _error = 'Подождите инициализации устройства');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final ApiClient api = AppScope.of(context).apiClient;

    try {
      await api.login(
        login: login,
        password: password,
        deviceFingerprint: fp,
        deviceModel: _deviceModel,
        deviceOs: _deviceOs,
      );
      final me = await api.getMe();
      await _maybePersistSession(login, me);
      await AccountStorage.upsert(me);
      await PushService.initAndGetToken(api);
      if (!mounted) return;
      final onboardingDone = await OnboardingPrefs.isDone();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        onboardingDone ? '/home' : '/onboarding-permissions',
      );
    } on AccountBannedException catch (e) {
      if (!mounted) return;
      await showAccountBannedDialog(context, e);
    } on MustRequestTransferException catch (_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        '/device-transfer-request',
        arguments: <String, dynamic>{
          'login': login,
          'password': password,
        },
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
        title: const Text('Вход'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) async {
              if (v == 'manage') await _openSavedAccountsManager();
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'manage', child: Text('Управление сохранёнными')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'LeWoGram',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Войдите в аккаунт',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                      CheckboxListTile(
                        value: _rememberMe,
                        onChanged: _loading
                            ? null
                            : (v) =>
                                setState(() => _rememberMe = v ?? false),
                        title: const Text('Запомнить на этом устройстве'),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: (_loading || !_fpReady) ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Войти'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => Navigator.of(context).pushNamed('/register'),
                child: const Text('Нет аккаунта? Зарегистрироваться'),
              ),
              if (_saved.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Быстрый вход',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ..._saved.map(
                  (r) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.login),
                      title: Text(r.label ?? r.login),
                      subtitle: Text(r.login),
                      onTap: (_loading || !_fpReady)
                          ? null
                          : () => _quickLogin(r),
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
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
