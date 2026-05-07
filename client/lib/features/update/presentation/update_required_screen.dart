import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Блокирующий экран: клиент ниже [minimumVersion]. Назад не закрывает (PopScope).
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.currentVersion,
    required this.minimumVersion,
    required this.updateUrl,
  });

  final String currentVersion;
  final String minimumVersion;
  final String updateUrl;

  Future<void> _openUrl() async {
    final u = Uri.tryParse(updateUrl.trim());
    if (u == null) return;
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.system_update_alt, size: 56, color: cs.primary),
                const SizedBox(height: 24),
                Text(
                  'Требуется обновление',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Установленная версия $currentVersion ниже минимальной '
                  '$minimumVersion. Обновите приложение, чтобы продолжить.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _openUrl,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Открыть страницу обновления'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
