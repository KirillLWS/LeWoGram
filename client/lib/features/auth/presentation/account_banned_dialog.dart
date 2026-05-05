import 'package:flutter/material.dart';
import 'package:lewogram_client/core/network/account_banned_exception.dart';

/// Модальное окно: аккаунт заблокирован (вход или сессия).
Future<void> showAccountBannedDialog(
  BuildContext context,
  AccountBannedException e,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final remaining = e.remainingSeconds;
      String? remainingLabel;
      if (e.accountStatus == 'temp_banned' && remaining != null) {
        final d = Duration(seconds: remaining);
        final h = d.inHours;
        final m = d.inMinutes.remainder(60);
        final s = d.inSeconds.remainder(60);
        if (h > 0) {
          remainingLabel = 'Осталось: $hч $mм';
        } else if (m > 0) {
          remainingLabel = 'Осталось: $mм $sс';
        } else {
          remainingLabel = 'Осталось: $sс';
        }
      }
      return AlertDialog(
        icon: Icon(Icons.block, color: theme.colorScheme.error),
        title: const Text('Доступ ограничен'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.reason),
              if (remainingLabel != null) ...[
                const SizedBox(height: 12),
                Text(
                  remainingLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              if (e.banUntil != null && e.banUntil!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'До: ${e.banUntil}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Понятно'),
          ),
        ],
      );
    },
  );
}
