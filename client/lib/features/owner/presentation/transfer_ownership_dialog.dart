import 'package:flutter/material.dart';
import 'package:lewogram_client/features/owner/data/transfer_ownership_result.dart';

/// Заглушка: выбор получателя и роли себя после передачи. Результат через [Navigator.pop].
Future<TransferOwnershipResult?> showTransferOwnershipDialog(
  BuildContext context,
) {
  return showDialog<TransferOwnershipResult>(
    context: context,
    builder: (ctx) => const _TransferOwnershipDialogBody(),
  );
}

class _TransferOwnershipDialogBody extends StatefulWidget {
  const _TransferOwnershipDialogBody();

  @override
  State<_TransferOwnershipDialogBody> createState() =>
      _TransferOwnershipDialogBodyState();
}

class _TransferOwnershipDialogBodyState extends State<_TransferOwnershipDialogBody> {
  static const _placeholderTargets = <({String id, String label})>[
    (id: 'user_stub_1', label: 'Пользователь (заглушка) 1'),
    (id: 'user_stub_2', label: 'Пользователь (заглушка) 2'),
  ];

  static const _selfRoles = <String>[
    'member',
    'moderator',
    'admin',
  ];

  late String _targetId;
  late String _selfRole;

  @override
  void initState() {
    super.initState();
    _targetId = _placeholderTargets.first.id;
    _selfRole = _selfRoles.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      title: const Text('Передать владение'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Получатель',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            DropdownMenu<String>(
              initialSelection: _targetId,
              label: const Text('Целевой пользователь'),
              dropdownMenuEntries: _placeholderTargets
                  .map(
                    (e) => DropdownMenuEntry<String>(
                      value: e.id,
                      label: e.label,
                    ),
                  )
                  .toList(),
              onSelected: (v) {
                if (v != null) setState(() => _targetId = v);
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Ваша роль после передачи',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: _selfRoles
                  .map(
                    (r) => ButtonSegment<String>(
                      value: r,
                      label: Text(r),
                    ),
                  )
                  .toList(),
              selected: {_selfRole},
              onSelectionChanged: (set) {
                setState(() => _selfRole = set.first);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              TransferOwnershipResult(
                targetUserId: _targetId,
                selfRoleAfterTransfer: _selfRole,
              ),
            );
          },
          child: const Text('Передать'),
        ),
      ],
    );
  }
}
