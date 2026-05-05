import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'package:lewogram_client/core/onboarding/onboarding_prefs.dart';
import 'package:lewogram_client/core/permissions/permissions_service.dart';

class _PermissionCardData {
  const _PermissionCardData({
    required this.permission,
    required this.icon,
    required this.title,
    required this.rationale,
  });

  final AppPermission permission;
  final IconData icon;
  final String title;
  final String rationale;
}

/// Первичный онбординг: по одному разрешению с пояснением, без массового запроса.
class PermissionsOnboardingScreen extends StatefulWidget {
  const PermissionsOnboardingScreen({super.key});

  @override
  State<PermissionsOnboardingScreen> createState() =>
      _PermissionsOnboardingScreenState();
}

class _PermissionsOnboardingScreenState extends State<PermissionsOnboardingScreen> {
  final PermissionsService _service = PermissionsService();
  final Map<AppPermission, ph.PermissionStatus> _status = {};

  static const List<_PermissionCardData> _cards = [
    _PermissionCardData(
      permission: AppPermission.camera,
      icon: Icons.photo_camera_outlined,
      title: 'Камера',
      rationale:
          'Чтобы делать фото для аватара и отправлять снимки в чатах, когда вы сами нажимаете «Камера».',
    ),
    _PermissionCardData(
      permission: AppPermission.microphone,
      icon: Icons.mic_outlined,
      title: 'Микрофон',
      rationale:
          'Для будущих голосовых сообщений и звонков — только если вы решите их использовать.',
    ),
    _PermissionCardData(
      permission: AppPermission.photos,
      icon: Icons.photo_library_outlined,
      title: 'Фото и медиа',
      rationale:
          'Чтобы выбрать аватар и вложения из галереи на Android 13+ и более старых версиях.',
    ),
    _PermissionCardData(
      permission: AppPermission.location,
      icon: Icons.location_on_outlined,
      title: 'Геолокация',
      rationale:
          'Если появятся функции «рядом со мной» или метки в чате — только по вашему действию.',
    ),
    _PermissionCardData(
      permission: AppPermission.notifications,
      icon: Icons.notifications_outlined,
      title: 'Уведомления',
      rationale:
          'Чтобы показывать новые сообщения и заявки в друзья, когда приложение в фоне.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
  }

  Future<void> _refreshAll() async {
    for (final c in _cards) {
      final perm = _nativeFor(c.permission);
      final s = await perm.status;
      if (mounted) setState(() => _status[c.permission] = s);
    }
  }

  ph.Permission _nativeFor(AppPermission p) {
    switch (p) {
      case AppPermission.camera:
        return ph.Permission.camera;
      case AppPermission.microphone:
        return ph.Permission.microphone;
      case AppPermission.photos:
        return ph.Permission.photos;
      case AppPermission.location:
        return ph.Permission.locationWhenInUse;
      case AppPermission.notifications:
        return ph.Permission.notification;
    }
  }

  String _statusLabel(ph.PermissionStatus s) {
    if (s.isGranted || s.isLimited) return '✓';
    if (s.isPermanentlyDenied) return 'Запрещено навсегда';
    return 'Не выдано';
  }

  Future<void> _requestOne(AppPermission p) async {
    await _service.request(p);
    await _refreshAll();
  }

  Future<void> _openSettings() async {
    await _service.openAppSettings();
    await _refreshAll();
  }

  Future<void> _finish() async {
    await OnboardingPrefs.setDone();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Доступы LeWoGram')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Text(
                    'Ниже — что может понадобиться приложению. Разрешения запрашиваются только по вашей кнопке, без пакетного окна.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final c in _cards) _buildCard(context, c),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _finish,
                  child: const Text('Готово'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, _PermissionCardData c) {
    final s = _status[c.permission] ?? ph.PermissionStatus.denied;
    final statusText = _statusLabel(s);
    final granted = s.isGranted || s.isLimited;
    final permanent = s.isPermanentlyDenied;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(c.icon, size: 32, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        c.rationale,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Статус: $statusText',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: permanent
                  ? TextButton(
                      onPressed: _openSettings,
                      child: const Text('Открыть настройки'),
                    )
                  : FilledButton.tonal(
                      onPressed: granted ? null : () => _requestOne(c.permission),
                      child: Text(granted ? 'Выдано' : 'Разрешить'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
