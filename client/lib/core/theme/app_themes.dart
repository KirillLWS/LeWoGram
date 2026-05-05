import 'package:flutter/material.dart';

/// Идентификаторы тем (имена совпадают с ключом в SharedPreferences).
enum AppThemeKind {
  defaultLight,
  neonGlitch,
  iosLike,
}

abstract final class AppThemeKindStorage {
  static AppThemeKind parse(String? stored) {
    if (stored == null) return AppThemeKind.defaultLight;
    for (final v in AppThemeKind.values) {
      if (v.name == stored) return v;
    }
    return AppThemeKind.defaultLight;
  }
}

/// Три готовые темы для [MaterialApp.theme].
abstract final class AppThemes {
  static ThemeData theme(AppThemeKind kind) {
    switch (kind) {
      case AppThemeKind.defaultLight:
        return defaultLight();
      case AppThemeKind.neonGlitch:
        return neonGlitch();
      case AppThemeKind.iosLike:
        return iosLike();
    }
  }

  /// Светлая тема по умолчанию (teal seed).
  static ThemeData defaultLight() {
    final cs = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.light,
    );
    final r12 = BorderRadius.circular(12);
    final r16 = BorderRadius.circular(16);
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: r16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: r12)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: r12)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: r12)),
      ),
    );
  }

  static const Color _neonBg = Color(0xFF0B0B12);
  static const Color _neonSurface = Color(0xFF131321);
  static const Color _neonPrimary = Color(0xFF7C4DFF);
  static const Color _neonSecondary = Color(0xFF00E5FF);
  static const Color _neonError = Color(0xFFFF4081);

  /// Тёмная «неон / глитч».
  static ThemeData neonGlitch() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    var cs = ColorScheme.fromSeed(
      seedColor: _neonPrimary,
      brightness: Brightness.dark,
    );
    cs = cs.copyWith(
      surface: _neonSurface,
      surfaceContainerLow: _neonSurface,
      surfaceContainer: const Color(0xFF18182A),
      surfaceContainerHigh: const Color(0xFF1E1E32),
      surfaceContainerHighest: const Color(0xFF252538),
      secondary: _neonSecondary,
      onSecondary: _neonBg,
      secondaryContainer: _neonSecondary.withValues(alpha: 0.22),
      onSecondaryContainer: _neonSecondary,
      error: _neonError,
      onError: Colors.black,
      primary: _neonPrimary,
      onPrimary: Colors.white,
    );

    var tt = base.textTheme;
    tt = tt.copyWith(
      headlineLarge: tt.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
      headlineMedium: tt.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
      headlineSmall: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      titleLarge: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      titleMedium: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      labelMedium: tt.labelMedium?.copyWith(
        fontFamily: 'monospace',
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      labelSmall: tt.labelSmall?.copyWith(
        fontFamily: 'monospace',
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    const r20 = BorderRadius.all(Radius.circular(20));
    final glow = _neonPrimary.withValues(alpha: 0.18);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _neonBg,
      colorScheme: cs,
      textTheme: tt,
      cardTheme: CardThemeData(
        color: _neonSurface,
        elevation: 10,
        shadowColor: glow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: r20),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _neonSurface,
        side: BorderSide(color: _neonPrimary.withValues(alpha: 0.45)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(
          color: cs.onSurface,
          fontFamily: 'monospace',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: r20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: r20),
        ),
      ),
      dividerTheme: DividerThemeData(color: cs.outlineVariant, thickness: 1),
    );
  }

  static const Color _iosBg = Color(0xFFF2F2F7);
  static const Color _iosSurface = Color(0xFFFFFFFF);
  static const Color _iosPrimary = Color(0xFF007AFF);
  static const Color _iosError = Color(0xFFFF3B30);
  static const Color _iosSecondary = Color(0xFF34C759);

  /// Светлая в духе Apple HIG (системный шрифт, без SF Pro).
  static ThemeData iosLike() {
    final cs = ColorScheme.light(
      brightness: Brightness.light,
      primary: _iosPrimary,
      onPrimary: Colors.white,
      primaryContainer: _iosPrimary.withValues(alpha: 0.12),
      onPrimaryContainer: _iosPrimary,
      secondary: _iosSecondary,
      onSecondary: Colors.white,
      secondaryContainer: _iosSecondary.withValues(alpha: 0.15),
      onSecondaryContainer: const Color(0xFF1C1C1E),
      surface: _iosSurface,
      onSurface: const Color(0xFF1C1C1E),
      onSurfaceVariant: const Color(0xFF636366),
      surfaceContainerHighest: const Color(0xFFE5E5EA),
      surfaceContainerHigh: const Color(0xFFECECF0),
      surfaceContainer: const Color(0xFFF2F2F7),
      surfaceContainerLow: _iosBg,
      error: _iosError,
      onError: Colors.white,
      // [ColorScheme.light] omits these by default; unset errorContainer falls back
      // to [error], which breaks tonal destructive buttons (red label on red fill).
      errorContainer: Color.alphaBlend(
        _iosError.withValues(alpha: 0.14),
        _iosSurface,
      ),
      onErrorContainer: const Color(0xFF930006),
      outline: const Color(0xFFC6C6C8),
      outlineVariant: const Color(0xFFE5E5EA),
    );

    final base = ThemeData(brightness: Brightness.light, useMaterial3: true);
    var tt = base.textTheme.apply(
      bodyColor: cs.onSurface,
      displayColor: cs.onSurface,
    );
    tt = tt.copyWith(
      headlineLarge: tt.headlineLarge?.copyWith(
        letterSpacing: -0.5,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: tt.headlineMedium?.copyWith(
        letterSpacing: -0.4,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: tt.headlineSmall?.copyWith(
        letterSpacing: -0.35,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: tt.titleLarge?.copyWith(
        letterSpacing: -0.35,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: tt.titleMedium?.copyWith(
        letterSpacing: -0.25,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: tt.titleSmall?.copyWith(
        letterSpacing: -0.2,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: tt.bodyLarge?.copyWith(letterSpacing: -0.15),
      bodyMedium: tt.bodyMedium?.copyWith(letterSpacing: -0.1),
      bodySmall: tt.bodySmall?.copyWith(letterSpacing: -0.05),
    );

    const r12 = BorderRadius.all(Radius.circular(12));

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _iosBg,
      colorScheme: cs,
      textTheme: tt,
      cardTheme: CardThemeData(
        color: _iosSurface,
        elevation: 0.5,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: r12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: r12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: r12),
        ),
      ),
      dividerTheme: DividerThemeData(
        thickness: 0.5,
        color: cs.outlineVariant,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: _iosPrimary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            letterSpacing: -0.1,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
