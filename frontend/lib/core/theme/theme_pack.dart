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
      lightAccent: Color(parseColor('lightAccent', 0xFF26A17B)),
      darkAccent: Color(parseColor('darkAccent', 0xFF7AA2F7)),
      highContrastAccent: Color(parseColor('highContrastAccent', 0xFF000000)),
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
  static const splitwise = ThemePack(
    familyId: 'splitwise',
    displayName: 'Splitwise',
    lightAccent: Color(0xFF26A17B),
    darkAccent: Color(0xFF1A8F6C),
    highContrastAccent: Color(0xFF000000),
  );

  static const tokyoNight = ThemePack(
    familyId: 'tokyoNight',
    displayName: 'Tokyo Night',
    lightAccent: Color(0xFF7AA2F7),
    darkAccent: Color(0xFF7DCFFF),
    highContrastAccent: Color(0xFF1D1D1D),
  );

  static const mint = ThemePack(
    familyId: 'mint',
    displayName: 'Mint',
    lightAccent: Color(0xFF3FBF9B),
    darkAccent: Color(0xFF2FAE8E),
    highContrastAccent: Color(0xFF0B3D2E),
  );
}
