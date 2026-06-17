import 'package:expense_tracker/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

class ThemePack {
  const ThemePack({
    required this.familyId,
    required this.displayName,
    required this.lightAccent,
    required this.darkAccent,
    required this.highContrastAccent,
  });

  final String familyId;
  final String displayName;
  final Color lightAccent;
  final Color darkAccent;
  final Color highContrastAccent;

  factory ThemePack.fromJson(Map<String, dynamic> json) {
    int parseColor(String key, int fallback) {
      final raw = json[key];
      if (raw is int) {
        return raw;
      }
      if (raw is String) {
        final normalized = raw.replaceFirst('#', '');
        return int.tryParse(normalized, radix: 16) ?? fallback;
      }
      return fallback;
    }

    return ThemePack(
      familyId: (json['familyId'] ?? 'custom').toString(),
      displayName: (json['displayName'] ?? 'Custom').toString(),
      lightAccent: Color(
        parseColor('lightAccent', AppPalette.accent.toARGB32()),
      ),
      darkAccent: Color(parseColor('darkAccent', AppPalette.accent.toARGB32())),
      highContrastAccent: Color(parseColor('highContrastAccent', 0xFF1D1D1D)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'familyId': familyId,
      'displayName': displayName,
      'lightAccent': lightAccent.toARGB32(),
      'darkAccent': darkAccent.toARGB32(),
      'highContrastAccent': highContrastAccent.toARGB32(),
    };
  }
}

class ThemePackCatalog {
  static const tokyoNight = ThemePack(
    familyId: 'tokyoNight',
    displayName: 'Hybrid',
    lightAccent: AppPalette.accent,
    darkAccent: AppPalette.accent,
    highContrastAccent: Color(0xFF1D1D1D),
  );

  static const mint = ThemePack(
    familyId: 'mint',
    displayName: 'Mint',
    lightAccent: AppPalette.mint,
    darkAccent: AppPalette.accentStrong,
    highContrastAccent: Color(0xFF0B3D2E),
  );
}
