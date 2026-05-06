import 'package:flutter/material.dart';
import 'package:lewogram_client/core/config/app_config.dart';
import 'package:lewogram_client/core/network/api_client.dart';

/// Диагностика: базовый URL и ответ GET `/`.
class DeveloperDiagnosticsScreen extends StatelessWidget {
  const DeveloperDiagnosticsScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Отладка')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: apiClient.fetchRootHealth(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final err = snap.error;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Base URL', style: theme.textTheme.titleSmall),
              const SelectableText(AppConfig.baseUrl),
              const SizedBox(height: 16),
              Text('GET /', style: theme.textTheme.titleSmall),
              if (err != null)
                Text('$err', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error))
              else
                SelectableText(snap.data.toString()),
            ],
          );
        },
      ),
    );
  }
}

/// Сервис: то же подключение к корню API (реальный запрос, не заглушка).
class ServiceDiagnosticsScreen extends StatelessWidget {
  const ServiceDiagnosticsScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Сервис')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: apiClient.fetchRootHealth(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final err = snap.error;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Состояние API', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                if (err != null)
                  Text('$err', style: TextStyle(color: theme.colorScheme.error))
                else
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(snap.data.toString()),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
