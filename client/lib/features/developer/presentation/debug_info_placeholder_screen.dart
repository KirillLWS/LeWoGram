import 'package:flutter/material.dart';

/// Заглушка экрана отладочной информации (сборка, флаги, логи — позже).
class DebugInfoPlaceholderScreen extends StatelessWidget {
  const DebugInfoPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Отладка')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.bug_report_outlined, size: 48, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                'Отладочные данные',
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Здесь будут версия клиента, флаги окружения и инструменты диагностики.',
                style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
