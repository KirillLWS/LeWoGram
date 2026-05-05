import 'package:flutter/material.dart';

import '../data/user_public_profile.dart';

/// Профиль другого пользователя. [onWrite] — создание/открытие директа (координатор).
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.profile,
    required this.onWrite,
  });

  final UserPublicProfile profile;

  /// Координатор реализует `POST /messages/chats/direct` и навигацию в чат.
  final Future<void> Function(int otherUserId) onWrite;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _writeBusy = false;

  Future<void> _onWritePressed() async {
    if (_writeBusy) return;
    setState(() => _writeBusy = true);
    try {
      await widget.onWrite(widget.profile.id);
    } finally {
      if (mounted) setState(() => _writeBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final p = widget.profile;
    final title = p.displayName?.trim().isNotEmpty == true
        ? p.displayName!.trim()
        : p.username;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: CircleAvatar(
                radius: 56,
                backgroundColor: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  size: 64,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              p.displayName?.trim().isNotEmpty == true
                  ? p.displayName!.trim()
                  : p.username,
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '@${p.username}',
              style: textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (p.about != null && p.about!.trim().isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                p.about!.trim(),
                style: textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _writeBusy ? null : _onWritePressed,
              child: _writeBusy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Написать'),
            ),
          ],
        ),
      ),
    );
  }
}
