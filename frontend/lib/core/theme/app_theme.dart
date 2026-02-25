import 'package:expense_tracker/core/theme/theme_pack.dart';
import 'package:expense_tracker/features/theme/cubit/theme_cubit.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppThemeFactory {
  static ThemeData build(ThemeState state) {
    final pack = _packForFamily(state.family);
    final brightness = _brightnessFor(state.variant);
    final highContrast = state.variant == ThemeVariant.highContrast;
    final accent = _accentFor(state, pack);

    final base = ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
      ),
      useMaterial3: true,
    );

    final scaffoldBg = switch (state.variant) {
      ThemeVariant.dark => const Color(0xFF111318),
      ThemeVariant.custom => const Color(0xFF111318),
      ThemeVariant.highContrast => const Color(0xFFFFFFFF),
      ThemeVariant.light => const Color(0xFFF7F8F9),
    };

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
      cardTheme: base.cardTheme.copyWith(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        indicatorColor: accent.withValues(alpha: highContrast ? 0.36 : 0.18),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: accent,
      ),
      textTheme: highContrast
          ? base.textTheme.apply(
              bodyColor: brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
              displayColor: brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            )
          : base.textTheme,
    );
  }

  static ThemePack _packForFamily(ThemeFamily family) {
    return switch (family) {
      ThemeFamily.splitwise => ThemePackCatalog.splitwise,
      ThemeFamily.tokyoNight => ThemePackCatalog.tokyoNight,
      ThemeFamily.mint => ThemePackCatalog.mint,
    };
  }

  static Color _accentFor(ThemeState state, ThemePack pack) {
    return switch (state.variant) {
      ThemeVariant.light => pack.lightAccent,
      ThemeVariant.dark => pack.darkAccent,
      ThemeVariant.highContrast => pack.highContrastAccent,
      ThemeVariant.custom => state.customAccent,
    };
  }

  static Brightness _brightnessFor(ThemeVariant variant) {
    return switch (variant) {
      ThemeVariant.dark => Brightness.dark,
      ThemeVariant.custom => Brightness.dark,
      ThemeVariant.light => Brightness.light,
      ThemeVariant.highContrast => Brightness.light,
    };
  }
}
