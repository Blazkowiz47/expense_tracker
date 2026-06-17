part of 'theme_cubit.dart';

enum ThemeFamily { tokyoNight, mint }

enum ThemeVariant { light, dark, highContrast, custom }

class ThemeState extends Equatable {
  const ThemeState({
    this.family = ThemeFamily.tokyoNight,
    this.variant = ThemeVariant.light,
    this.customAccentValue = AppPalette.accentValue,
  });

  final ThemeFamily family;
  final ThemeVariant variant;
  final int customAccentValue;

  Color get customAccent => Color(customAccentValue);

  ThemeState copyWith({
    ThemeFamily? family,
    ThemeVariant? variant,
    int? customAccentValue,
  }) {
    return ThemeState(
      family: family ?? this.family,
      variant: variant ?? this.variant,
      customAccentValue: customAccentValue ?? this.customAccentValue,
    );
  }

  @override
  List<Object?> get props => [family, variant, customAccentValue];
}
