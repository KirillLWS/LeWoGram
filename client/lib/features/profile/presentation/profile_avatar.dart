import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:lewogram_client/core/media/avatar_network_url.dart';
import 'package:lewogram_client/features/profile/data/profile_user.dart';

/// Круглый аватар: сеть (кэш), локальный файл (не web) или инициалы.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.user,
    this.effectiveAvatarRef,
    required this.radius,
  });

  final ProfileUser user;
  final String? effectiveAvatarRef;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ref = effectiveAvatarRef?.trim();
    final initial = _initial(user.primaryLabel);
    final size = radius * 2;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final memW = (size * dpr).round();

    if (ref != null && ref.isNotEmpty) {
      final lower = ref.toLowerCase();
      final networkUrl = (lower.startsWith('http://') || lower.startsWith('https://'))
          ? ref
          : resolveAvatarImageUrl(ref);

      if (networkUrl != null) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: scheme.primaryContainer,
          child: ClipOval(
            child: CachedNetworkImage(
              imageUrl: networkUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              memCacheWidth: memW,
              fadeInDuration: Duration.zero,
              placeholder: (_, __) => SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              errorWidget: (_, url, err) {
                logAvatarLoadFailure(url, err);
                return _placeholder(scheme, textTheme, initial, size);
              },
            ),
          ),
        );
      }
      if (!kIsWeb) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: scheme.primaryContainer,
          child: ClipOval(
            child: Image.file(
              File(ref),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, err, __) {
                logAvatarLoadFailure(ref, err);
                return _placeholder(scheme, textTheme, initial, size);
              },
            ),
          ),
        );
      }
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(
        initial,
        style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  static Widget _placeholder(ColorScheme scheme, TextTheme textTheme, String initial, double size) {
    return Container(
      width: size,
      height: size,
      color: scheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }

  static String _initial(String s) {
    final t = s.trim();
    if (t.isEmpty) return '?';
    final cp = t.runes.first;
    return String.fromCharCode(cp).toUpperCase();
  }
}
