import 'package:expense_tracker/core/theme/app_palette.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'theme_state.dart';

class ThemeCubit extends HydratedCubit<ThemeState> {
  ThemeCubit() : super(const ThemeState());

  void setFamily(ThemeFamily family) {
    emit(state.copyWith(family: family));
  }

  void setVariant(ThemeVariant variant) {
    emit(state.copyWith(variant: variant));
  }

  void setCustomAccent(Color color) {
    emit(state.copyWith(customAccentValue: color.toARGB32()));
  }

  void resetDefaults() {
    emit(const ThemeState());
  }

  @override
  ThemeState? fromJson(Map<String, dynamic> json) {
    final familyName = (json['family'] ?? '').toString();
    final variantName = (json['variant'] ?? '').toString();
    final accentValue = json['customAccentValue'] as int?;
    final defaultState = const ThemeState();

    final family = switch (familyName) {
      'mint' => ThemeFamily.mint,
      _ => ThemeFamily.tokyoNight,
    };
    final variant = ThemeVariant.values.firstWhere(
      (v) => v.name == variantName,
      orElse: () => ThemeVariant.light,
    );
    final customAccentValue = switch (accentValue) {
      0xFF26A17B => defaultState.customAccentValue,
      0xFF7AA2F7 => defaultState.customAccentValue,
      0xFF7DCFFF => defaultState.customAccentValue,
      final int value => value,
      _ => defaultState.customAccentValue,
    };

    return ThemeState(
      family: family,
      variant: variant,
      customAccentValue: customAccentValue,
    );
  }

  @override
  Map<String, dynamic>? toJson(ThemeState state) {
    return {
      'family': state.family.name,
      'variant': state.variant.name,
      'customAccentValue': state.customAccentValue,
    };
  }
}
