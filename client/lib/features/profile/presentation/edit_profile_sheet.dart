import 'package:flutter/material.dart';

/// Нижняя модалка: отображаемое имя, ник, о себе и сохранение через [onSave].
class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({
    super.key,
    required this.initialDisplayName,
    required this.initialUsername,
    required this.initialAbout,
    this.onSave,
  });

  final String initialDisplayName;
  final String initialUsername;
  final String initialAbout;

  /// Координатор подключает API; при `null` кнопка «Сохранить» показывает подсказку.
  final Future<void> Function(String displayName, String username, String about)? onSave;

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  late final TextEditingController _displayName;
  late final TextEditingController _username;
  late final TextEditingController _about;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _displayName = TextEditingController(text: widget.initialDisplayName);
    _username = TextEditingController(text: widget.initialUsername);
    _about = TextEditingController(text: widget.initialAbout);
  }

  @override
  void dispose() {
    _displayName.dispose();
    _username.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final fn = widget.onSave;
    if (fn == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранение не подключено (координатор)')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await fn(
        _displayName.text.trim(),
        _username.text.trim(),
        _about.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: scheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(
              'Редактирование профиля',
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _displayName,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Отображаемое имя',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _username,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Имя пользователя',
                hintText: 'ник без @',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _about,
              textInputAction: TextInputAction.done,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'О себе',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Показать модалку редактирования; `true` если сохранено и закрыто.
Future<bool?> showEditProfileSheet(
  BuildContext context, {
  required String initialDisplayName,
  required String initialUsername,
  required String initialAbout,
  Future<void> Function(String displayName, String username, String about)? onSave,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: EditProfileSheet(
          initialDisplayName: initialDisplayName,
          initialUsername: initialUsername,
          initialAbout: initialAbout,
          onSave: onSave,
        ),
      );
    },
  );
}
