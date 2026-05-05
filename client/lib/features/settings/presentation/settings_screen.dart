import 'dart:async';

import 'package:flutter/material.dart';

import 'package:lewogram_client/app/app_scope.dart';
import 'package:lewogram_client/core/theme/app_themes.dart';
import 'package:lewogram_client/features/device_transfer/presentation/device_transfer_my_requests_screen.dart';

/// Настройки приложения: выбор темы и сброс к стандартной.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final controller = AppScope.of(context).themeController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final selected = controller.kind;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.history, color: scheme.primary),
                      title: const Text('Мои запросы на устройство'),
                      subtitle: const Text(
                        'Активные и прошлые заявки на вход с другого устройства',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const DeviceTransferMyRequestsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Тема',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Оформление применяется сразу ко всему приложению.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ThemeOptionRow(
                        title: 'Стандартная (светлая)',
                        subtitle: 'Teal, Material 3',
                        value: AppThemeKind.defaultLight,
                        selected: selected,
                        onSelect: () => unawaited(controller.setTheme(AppThemeKind.defaultLight)),
                      ),
                      _ThemePreviewStrip(theme: AppThemes.theme(AppThemeKind.defaultLight)),
                      _ThemeOptionRow(
                        title: 'Неон / глитч',
                        subtitle: 'Тёмная, акценты и свечение',
                        value: AppThemeKind.neonGlitch,
                        selected: selected,
                        onSelect: () => unawaited(controller.setTheme(AppThemeKind.neonGlitch)),
                      ),
                      _ThemePreviewStrip(theme: AppThemes.theme(AppThemeKind.neonGlitch)),
                      _ThemeOptionRow(
                        title: 'В стиле iOS',
                        subtitle: 'Светлая, системный шрифт',
                        value: AppThemeKind.iosLike,
                        selected: selected,
                        onSelect: () => unawaited(controller.setTheme(AppThemeKind.iosLike)),
                      ),
                      _ThemePreviewStrip(theme: AppThemes.theme(AppThemeKind.iosLike)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => unawaited(controller.resetToDefault()),
                        icon: const Icon(Icons.restore),
                        label: const Text('Сбросить к стандартной'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Строка выбора темы (аналог радио без устаревшего [RadioListTile] API).
class _ThemeOptionRow extends StatelessWidget {
  const _ThemeOptionRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final String subtitle;
  final AppThemeKind value;
  final AppThemeKind selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOn = selected == value;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(
        isOn ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isOn ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      selected: isOn,
      onTap: onSelect,
    );
  }
}

/// Мини-превью палитры темы.
class _ThemePreviewStrip extends StatelessWidget {
  const _ThemePreviewStrip({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Theme(
        data: theme,
        child: Builder(
          builder: (ctx) {
            final t = Theme.of(ctx);
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: _Swatch(color: cs.primary, label: 'Акцент'),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _Swatch(color: cs.secondary, label: 'Доп.'),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _Swatch(color: cs.error, label: 'Ошибка'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Aa',
                        style: t.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
