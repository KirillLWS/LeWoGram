import 'package:flutter/material.dart';
import 'package:lewogram_client/features/developer/presentation/debug_info_placeholder_screen.dart';
import 'package:lewogram_client/features/developer/presentation/service_info_placeholder_screen.dart';

/// Точка входа «разработчик»: переходы на заглушки отладки и сервиса.
class DeveloperHubScreen extends StatelessWidget {
  const DeveloperHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Разработчик')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Отладка'),
            subtitle: const Text('Сборка, диагностика — заглушка'),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const DebugInfoPlaceholderScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Сервис'),
            subtitle: const Text('API, соединение — заглушка'),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const ServiceInfoPlaceholderScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
