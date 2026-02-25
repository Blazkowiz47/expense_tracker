import 'package:expense_tracker/core/theme/app_theme.dart';
import 'package:expense_tracker/features/theme/cubit/theme_cubit.dart';
import 'package:expense_tracker/features/theme/view/theme_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    required Size size,
    required ThemeState state,
  }) async {
    final cubit = ThemeCubit()
      ..setFamily(state.family)
      ..setVariant(state.variant)
      ..setCustomAccent(state.customAccent);
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: BlocProvider.value(
          value: cubit,
          child: BlocBuilder<ThemeCubit, ThemeState>(
            builder: (context, current) {
              final theme = AppThemeFactory.build(current);
              return MaterialApp(
                theme: theme,
                darkTheme: theme,
                home: const ThemeSettingsPage(),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('theme settings custom variant golden', (tester) async {
    await pumpSettings(
      tester,
      size: const Size(430, 932),
      state: const ThemeState(
        family: ThemeFamily.tokyoNight,
        variant: ThemeVariant.custom,
        customAccentValue: 0xFFFF6B6B,
      ),
    );

    await expectLater(
      find.byType(ThemeSettingsPage),
      matchesGoldenFile('goldens/theme_settings_custom.png'),
    );
  });
}
