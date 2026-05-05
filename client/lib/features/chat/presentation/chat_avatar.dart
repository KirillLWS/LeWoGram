import 'package:flutter/material.dart';

/// First visible character of [title], uppercased, for letter fallback avatars.
String chatAvatarLetter(String title) {
  final t = title.trim();
  if (t.isEmpty) return '?';
  final it = t.runes.iterator;
  if (!it.moveNext()) return '?';
  return String.fromCharCode(it.current).toUpperCase();
}

/// Returns an absolute `http`/`https` URL suitable for [Image.network], or `null`.
String? resolveChatAvatarNetworkUrl(String? path) {
  if (path == null) return null;
  final s = path.trim();
  if (s.isEmpty) return null;
  final uri = Uri.tryParse(s);
  if (uri != null &&
      uri.hasScheme &&
      (uri.scheme == 'http' || uri.scheme == 'https')) {
    return uri.toString();
  }
  if (s.startsWith('//')) {
    final u = Uri.tryParse('https:$s');
    if (u != null && u.hasScheme) return u.toString();
  }
  return null;
}

/// Circular avatar: network image when [avatarPath] resolves to a URL, else [letter].
class ChatAvatarCircle extends StatelessWidget {
  const ChatAvatarCircle({
    super.key,
    required this.letter,
    this.avatarPath,
    this.radius = 22,
  });

  final String letter;
  final String? avatarPath;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final url = resolveChatAvatarNetworkUrl(avatarPath);
    final side = radius * 2;

    if (url != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        child: ClipOval(
          child: Image.network(
            url,
            width: side,
            height: side,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _letterFallback(
              theme: theme,
              cs: cs,
              letter: letter,
            ),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: SizedBox(
                  width: radius,
                  height: radius,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      child: Text(
        letter,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static Widget _letterFallback({
    required ThemeData theme,
    required ColorScheme cs,
    required String letter,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: cs.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.onPrimaryContainer,
        ),
      ),
    );
  }
}
