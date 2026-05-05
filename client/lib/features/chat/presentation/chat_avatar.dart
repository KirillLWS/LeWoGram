import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:lewogram_client/core/media/avatar_network_url.dart';

/// First visible character of [title], uppercased, for letter fallback avatars.
String chatAvatarLetter(String title) {
  final t = title.trim();
  if (t.isEmpty) return '?';
  final it = t.runes.iterator;
  if (!it.moveNext()) return '?';
  return String.fromCharCode(it.current).toUpperCase();
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
    final url = resolveAvatarImageUrl(avatarPath);
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
            errorWidget: (_, urlFailed, err) {
              logAvatarLoadFailure(urlFailed, err);
              return _letterFallback(
                theme: theme,
                cs: cs,
                letter: letter,
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
