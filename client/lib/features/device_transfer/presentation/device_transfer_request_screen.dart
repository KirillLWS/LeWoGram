import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/device/device_fingerprint.dart';
import 'package:lewogram_client/core/device/device_hardware_info.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Запрос на вход с нового устройства: POST /device-transfer/request (без JWT).
class DeviceTransferRequestScreen extends StatefulWidget {
  const DeviceTransferRequestScreen({
    super.key,
    this.initialLogin,
    this.initialPassword,
  });

  final String? initialLogin;
  final String? initialPassword;

  @override
  State<DeviceTransferRequestScreen> createState() =>
      _DeviceTransferRequestScreenState();
}

class _DeviceTransferRequestScreenState
    extends State<DeviceTransferRequestScreen> {
  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phraseCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _fingerprint = DeviceFingerprint();

  String _mode = 'add';
  bool _usePhrase = false;
  bool _loading = false;
  bool _fpReady = false;
  bool _deviceInfoReady = false;
  String? _deviceFingerprint;
  String _deviceModel = '';
  String _deviceOs = '';
  double? _geoLat;
  double? _geoLng;
  double? _geoAccuracyM;
  String? _geoNote;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialLogin != null && widget.initialLogin!.trim().isNotEmpty) {
      _loginCtrl.text = widget.initialLogin!.trim();
    }
    if (widget.initialPassword != null && widget.initialPassword!.isNotEmpty) {
      _passwordCtrl.text = widget.initialPassword!;
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final fp = await _fingerprint.getOrCreate();
    if (!mounted) return;
    setState(() {
      _deviceFingerprint = fp;
      _fpReady = true;
    });
    try {
      final hw = await readDeviceHardwareLabel();
      if (!mounted) return;
      setState(() {
        _deviceModel = hw.model;
        _deviceOs = hw.os;
        _deviceInfoReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deviceModel = 'Неизвестно';
        _deviceOs = 'Неизвестно';
        _deviceInfoReady = true;
      });
    }
  }

  Future<void> _requestGeo() async {
    setState(() {
      _geoNote = null;
      _error = null;
    });
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      setState(() {
        _geoNote =
            'Геолокация недоступна — запрос будет отправлен без координат.';
      });
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      setState(() {
        _geoLat = pos.latitude;
        _geoLng = pos.longitude;
        _geoAccuracyM = pos.accuracy;
        _geoNote = 'Координаты добавлены в запрос.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _geoNote = 'Не удалось получить координаты (можно отправить без них).';
      });
    }
  }

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    _phraseCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final login = _loginCtrl.text.trim();
    final password = _passwordCtrl.text;
    final phrase = _phraseCtrl.text.trim();
    final reason = _reasonCtrl.text.trim();
    final fp = _deviceFingerprint;

    if (login.isEmpty || reason.length < 10) {
      setState(
        () => _error = 'Укажите логин и причину не короче 10 символов',
      );
      return;
    }
    if (!_usePhrase && password.isEmpty) {
      setState(() => _error = 'Введите пароль');
      return;
    }
    if (_usePhrase && phrase.isEmpty) {
      setState(() => _error = 'Введите фразу восстановления');
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

    final api = AppScope.of(context).apiClient;

    try {
      final res = await api.deviceTransferRequest(
        login: login,
        password: _usePhrase ? null : password,
        recoveryPhrase: _usePhrase ? phrase : null,
        mode: _mode,
        deviceFingerprint: fp,
        deviceModel: _deviceModel.isNotEmpty ? _deviceModel : null,
        deviceOs: _deviceOs.isNotEmpty ? _deviceOs : null,
        reason: reason,
        geoLat: _geoLat,
        geoLng: _geoLng,
        geoAccuracyM: _geoAccuracyM,
      );
      final id = (res['request_id'] as num?)?.toInt() ??
          (res['id'] as num).toInt();
      final code = res['short_code'] as String;
      if (!mounted) return;
      await Navigator.of(context).pushReplacementNamed(
        '/device-transfer-wait',
        arguments: <String, dynamic>{
          'requestId': id,
          'shortCode': code,
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
      appBar: AppBar(title: const Text('Новое устройство')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Запрос администратору',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'После отправки дождитесь подтверждения владельцем или главным '
                'администратором. Уведомление придёт на их устройства.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (!_deviceInfoReady)
                const LinearProgressIndicator()
              else
                Text(
                  'Устройство: $_deviceModel · $_deviceOs',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 20),
              TextField(
                controller: _loginCtrl,
                decoration: const InputDecoration(
                  labelText: 'Логин',
                  border: OutlineInputBorder(),
                ),
                autocorrect: false,
                enabled: !_loading,
              ),
              const SizedBox(height: 16),
              Text('Режим', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'add',
                    label: Text('Привязать дополнительно'),
                  ),
                  ButtonSegment<String>(
                    value: 'transfer',
                    label: Text('Полная смена'),
                  ),
                ],
                selected: <String>{_mode},
                onSelectionChanged: _loading
                    ? null
                    : (s) {
                        if (s.isEmpty) return;
                        setState(() => _mode = s.first);
                      },
              ),
              const SizedBox(height: 8),
              Text(
                _mode == 'add'
                    ? 'Старое устройство останется в сессии.'
                    : 'После подтверждения администратор может отозвать остальные сессии.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Войти по фразе восстановления вместо пароля'),
                value: _usePhrase,
                onChanged: _loading
                    ? null
                    : (v) => setState(() {
                          _usePhrase = v;
                        }),
              ),
              if (!_usePhrase)
                TextField(
                  controller: _passwordCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  enabled: !_loading,
                )
              else
                TextField(
                  controller: _phraseCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Фраза восстановления (12 слов)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  minLines: 2,
                  maxLines: 4,
                  enabled: !_loading,
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Причина запроса (от 10 символов)',
                  border: OutlineInputBorder(),
                  hintText: 'Например: купил новый телефон, старый больше не включается',
                ),
                minLines: 3,
                maxLines: 6,
                enabled: !_loading,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: (_loading || !_fpReady) ? null : _requestGeo,
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Разрешить геолокацию и добавить координаты'),
              ),
              if (_geoNote != null) ...[
                const SizedBox(height: 8),
                Text(
                  _geoNote!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: (_loading || !_fpReady || !_deviceInfoReady)
                    ? null
                    : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Отправить запрос'),
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
