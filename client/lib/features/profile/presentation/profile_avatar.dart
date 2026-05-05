import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:lewogram_client/features/profile/data/profile_user.dart';

/// Круглый аватар: сеть, локальный файл (не web) или инициалы.
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

    if (ref != null && ref.isNotEmpty) {
      final lower = ref.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://')) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: scheme.primaryContainer,
          child: ClipOval(
            child: Image.network(
              ref,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(scheme, textTheme, initial, size),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return SizedBox(
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
                );
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
              errorBuilder: (_, __, ___) => _placeholder(scheme, textTheme, initial, size),
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
