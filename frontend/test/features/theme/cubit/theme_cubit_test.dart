import 'package:expense_tracker/features/theme/cubit/theme_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeCubit', () {
    test('initial state is splitwise light', () {
      final cubit = ThemeCubit();
      expect(cubit.state.family, ThemeFamily.splitwise);
      expect(cubit.state.variant, ThemeVariant.light);
      cubit.close();
    });

    test('can update family variant and custom accent', () {
      final cubit = ThemeCubit();
      cubit.setFamily(ThemeFamily.tokyoNight);
      cubit.setVariant(ThemeVariant.custom);
      cubit.setCustomAccent(const Color(0xFFFF6B6B));

      expect(cubit.state.family, ThemeFamily.tokyoNight);
      expect(cubit.state.variant, ThemeVariant.custom);
      expect(cubit.state.customAccent, const Color(0xFFFF6B6B));
      cubit.close();
    });

    test('serializes and deserializes state for persistence', () {
      final cubit = ThemeCubit();
      final json = cubit.toJson(
        const ThemeState(
          family: ThemeFamily.tokyoNight,
          variant: ThemeVariant.highContrast,
          customAccentValue: 0xFF123456,
        ),
      );

      final restored = cubit.fromJson(json!);
      expect(restored, isNotNull);
      expect(restored!.family, ThemeFamily.tokyoNight);
      expect(restored.variant, ThemeVariant.highContrast);
      expect(restored.customAccentValue, 0xFF123456);
      cubit.close();
    });
  });
}
