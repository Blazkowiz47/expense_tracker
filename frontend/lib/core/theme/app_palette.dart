import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const accentValue = 0xFF26A17B;
  static const accent = Color(accentValue);
  static const accentStrong = Color(0xFF1A8F6C);
  static const accentSoft = Color(0xFFE6F4EE);
  static const positive = Color(0xFF1B8C67);

  static const negative = Color(0xFFBA1A1A);
  static const negativeSoft = Color(0xFFFDE7E7);
  static const warning = Color(0xFFC47B00);
  static const warningText = Color(0xFF8A5E00);
  static const warningSoft = Color(0xFFFFF4E0);
  static const expense = Color(0xFFE8A317);

  static const page = Color(0xFFF4F6F8);
  static const appBackground = Color(0xFFF7F8F9);
  static const shellBackground = Color(0xFFD5D9DE);
  static const track = Color(0xFFEEF0F3);
  static const neutralSoft = Color(0xFFF0F2F4);
  static const border = Color(0xFFE2E4E8);
  static const accentBorder = Color(0xFFC3E6D9);
  static const warningBorder = Color(0xFFF5DFA0);
  static const negativeBorder = Color(0xFFF6C6C6);
  static const inputBorder = Color(0xFF45474A);
  static const mutedText = Color(0xFF58646F);
  static const chartGrid = Color(0xFFE5E7EB);
  static const chartFill = Color(0xFFEAF6F1);
  static const chartLabel = Color(0xFF64748B);
  static const fieldFill = Color(0xFFF8FAFC);
  static const strongText = Color(0xFF111827);

  static const info = Color(0xFF7AA2F7);
  static const mint = Color(0xFF3FBF9B);
  static const purple = Color(0xFF9D7CFF);

  static const categoryPalette = <Color>[
    accentStrong,
    accent,
    mint,
    info,
    expense,
    purple,
  ];

  static const participantPalette = <Color>[
    Color(0xFF6EC8AA),
    Color(0xFF4DA58E),
    Color(0xFFE39A6B),
    Color(0xFF4F7AA2),
  ];

  static const mascotPalette = <Color>[
    Color(0xFF9BDDD0),
    Color(0xFF6CA6D9),
    Color(0xFFD96D8A),
    Color(0xFF9E80D9),
  ];
}
