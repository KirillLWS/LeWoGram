import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/onboarding/onboarding_prefs.dart';
import 'package:lewogram_client/core/push/push_service.dart';
import 'package:lewogram_client/core/storage/account_storage.dart';

/// Ожидание подтверждения админом: poll каждые 5 с.
class DeviceTransferWaitScreen extends StatefulWidget {
  const DeviceTransferWaitScreen({
    super.key,
    required this.requestId,
    required this.shortCode,
  });

  final int requestId;
  final String shortCode;

  @override
  State<DeviceTransferWaitScreen> createState() =>
      _DeviceTransferWaitScreenState();
}

class _DeviceTransferWaitScreenState extends State<DeviceTransferWaitScreen> {
  Timer? _timer;
  String? _statusText;
  String? _error;
  bool _done = false;
  bool _pollingStarted = false;
  ApiClient? _api;

  @override
  void initState() {
    super.initState();
    _statusText = 'Ожидание подтверждения…';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pollingStarted) return;
    _pollingStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _api = AppScope.of(context).apiClient;
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _pollOnce());
      unawaited(_pollOnce());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _pollOnce() async {
    if (!mounted || _done) return;
    final api = _api;
    if (api == null) return;

    try {
      final m = await api.deviceTransferPoll(
        requestId: widget.requestId,
        shortCode: widget.shortCode,
      );
      final st = m['status'] as String? ?? '';
      if (!mounted || _done) return;

      if (st == 'pending') {
        setState(() => _statusText = 'Запрос у администратора…');
        return;
      }

      if (st == 'approved') {
        final access = m['access_token'] as String?;
        final refresh = m['refresh_token'] as String?;
        if (access != null &&
            access.isNotEmpty &&
            refresh != null &&
            refresh.isNotEmpty) {
          _timer?.cancel();
          _done = true;
          await api.applyTokenPair(accessToken: access, refreshToken: refresh);
          final me = await api.getMe();
          await AccountStorage.upsert(me);
          await PushService.initAndGetToken(api);
          if (!mounted) return;
          final onboardingDone = await OnboardingPrefs.isDone();
          if (!mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil(
            onboardingDone ? '/home' : '/onboarding-permissions',
            (_) => false,
          );
        }
        return;
      }

      _timer?.cancel();
      _done = true;
      if (st == 'denied') {
        final note = m['reason'] as String?;
        setState(() {
          _statusText = null;
          _error = note != null && note.isNotEmpty
              ? 'Запрос отклонён: $note'
              : 'Запрос отклонён администратором.';
        });
        return;
      }
      if (st == 'expired' || st == 'cancelled') {
        setState(() {
          _statusText = null;
          _error = st == 'expired'
              ? 'Срок запроса истёк. Создайте новый запрос.'
              : 'Запрос отменён.';
        });
        return;
      }
      setState(() {
        _statusText = null;
        _error = 'Статус: $st';
      });
    } on ApiException catch (e) {
      if (e.statusCode == 410) {
        _timer?.cancel();
        _done = true;
        if (!mounted) return;
        setState(() {
          _statusText = null;
          _error =
              'Токены уже были получены ранее. Если вы не входили, обратитесь к администратору.';
        });
        return;
      }
      if (!mounted || _done) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted || _done) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = widget.shortCode;

    return Scaffold(
      appBar: AppBar(title: const Text('Подтверждение устройства')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Покажите этот код администратору при необходимости',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SelectableText(
                      code,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayMedium?.copyWith(
                        letterSpacing: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_statusText != null)
                Text(
                  _statusText!,
                  style: theme.textTheme.bodyLarge,
                ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/login',
                      (_) => false,
                    );
                  },
                  child: const Text('Назад на экран входа'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
