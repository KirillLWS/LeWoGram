import 'package:flutter/material.dart';

/// Заглушка экрана истории назначения ролей.
class RoleHistoryPlaceholderScreen extends StatelessWidget {
  const RoleHistoryPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('История ролей')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.history_outlined, size: 48, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                'Пока нет данных',
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Здесь появится журнал изменений ролей и сроков действия.',
                style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
