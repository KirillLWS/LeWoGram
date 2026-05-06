import 'package:flutter/material.dart';
import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/features/developer/presentation/developer_diagnostics_screens.dart';

/// Список инструментов Dev (без [Scaffold]) — для встраивания во вкладку владельца.
class DeveloperHubBody extends StatelessWidget {
  const DeveloperHubBody({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).apiClient;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Отладка'),
          subtitle: const Text('Base URL и ответ GET /'),
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => DeveloperDiagnosticsScreen(apiClient: api),
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Сервис'),
          subtitle: const Text('Проверка доступности API'),
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => ServiceDiagnosticsScreen(apiClient: api),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Точка входа разработчика: реальные запросы к API (корень сервера).
class DeveloperHubScreen extends StatelessWidget {
  const DeveloperHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dev')),
      body: const DeveloperHubBody(),
    );
  }
}
