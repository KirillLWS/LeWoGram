import 'package:flutter/material.dart';

/// Заглушка экрана сервисной информации (API, состояние соединения — позже).
class ServiceInfoPlaceholderScreen extends StatelessWidget {
  const ServiceInfoPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Сервис')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.dns_outlined, size: 48, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                'Сервисная информация',
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Здесь будут базовый URL API, статус WebSocket и служебные параметры.',
                style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
