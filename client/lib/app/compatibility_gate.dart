import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/app/session_gate.dart';
import 'package:lewogram_client/core/config/app_config.dart';
import 'package:lewogram_client/core/network/api_client.dart';
import 'package:lewogram_client/core/version/version_compare.dart';
import 'package:lewogram_client/features/update/presentation/update_required_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Перед сессией: проверка версии по публичному GET `/client/requirements`.
class CompatibilityGate extends StatefulWidget {
  const CompatibilityGate({super.key});

  @override
  State<CompatibilityGate> createState() => _CompatibilityGateState();
}

class _CompatibilityGateState extends State<CompatibilityGate> {
  _GateState _state = _GateState.loading;
  String? _errorMessage;
  String _currentVersion = '';
  String _minVersion = '';
  String _apkUrl = '';
  String _infoUrl = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (AppConfig.skipClientVersionCheck) {
      if (!mounted) return;
      setState(() => _state = _GateState.ready);
      return;
    }

    if (!mounted) return;
    final api = AppScope.of(context).apiClient;

    setState(() {
      _state = _GateState.loading;
      _errorMessage = null;
    });

    try {
      final info = await PackageInfo.fromPlatform();
      final req = await api.fetchClientRequirements();
      final min = req['min_client_version']?.toString().trim() ?? '0.0.1';
      final ver = info.version.trim();

      if (!mounted) return;
      if (isClientVersionBelowMinimum(ver, min)) {
        setState(() {
          _state = _GateState.blocked;
          _currentVersion = ver;
          _minVersion = min;
          _apkUrl = req['apk_url']?.toString().trim() ?? '';
          _infoUrl = req['update_url']?.toString().trim() ?? '';
        });
        return;
      }

      setState(() => _state = _GateState.ready);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _GateState.error;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _GateState.error;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _GateState.loading:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case _GateState.blocked:
        return UpdateRequiredScreen(
          currentVersion: _currentVersion,
          minimumVersion: _minVersion,
          apkUrlOrPath: _apkUrl,
          infoUrl: _infoUrl,
        );
      case _GateState.error:
        final msg = _errorMessage ?? 'Неизвестная ошибка';
        return PopScope(
          canPop: false,
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Нужна сеть для проверки версии приложения.',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      msg,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _check,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      case _GateState.ready:
        return const SessionGate();
    }
  }
}

enum _GateState { loading, blocked, error, ready }
