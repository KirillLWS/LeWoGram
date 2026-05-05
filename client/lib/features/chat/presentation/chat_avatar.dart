import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:lewogram_client/core/config/app_config.dart';

/// First visible character of [title], uppercased, for letter fallback avatars.
String chatAvatarLetter(String title) {
  final t = title.trim();
  if (t.isEmpty) return '?';
  final it = t.runes.iterator;
  if (!it.moveNext()) return '?';
  return String.fromCharCode(it.current).toUpperCase();
}

/// Returns an absolute `http`/`https` URL for кэшируемого изображения, или `null`.
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
  if (!s.contains('://')) {
    final base = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final sub = s.startsWith('/') ? s.substring(1) : s;
    return Uri.parse('$base/$sub').toString();
  }
  return null;
}

/// Circular avatar: cached network image when [avatarPath] resolves to a URL, else [letter].
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
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final memW = (side * dpr).round();

    if (url != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            width: side,
            height: side,
            fit: BoxFit.cover,
            memCacheWidth: memW,
            fadeInDuration: Duration.zero,
            placeholder: (_, __) => Center(
              child: SizedBox(
                width: radius,
                height: radius,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
            ),
            errorWidget: (_, __, ___) => _letterFallback(
              theme: theme,
              cs: cs,
              letter: letter,
            ),
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
