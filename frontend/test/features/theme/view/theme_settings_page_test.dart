import 'package:expense_tracker/core/theme/app_theme.dart';
import 'package:expense_tracker/features/theme/cubit/theme_cubit.dart';
import 'package:expense_tracker/features/theme/view/theme_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ThemeCubit> pumpSettings(WidgetTester tester) async {
    final cubit = ThemeCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, state) {
            final theme = AppThemeFactory.build(state);
            return MaterialApp(
              theme: theme,
              darkTheme: theme,
              home: const ThemeSettingsPage(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('shows hybrid and mint as the theme families', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Hybrid'), findsOneWidget);
    expect(find.text('Splitwise'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<ThemeFamily>));
    await tester.pumpAndSettle();

    expect(find.text('Mint'), findsOneWidget);
    expect(find.text('Splitwise'), findsNothing);
  });

  testWidgets('reset returns to hybrid', (tester) async {
    final cubit = await pumpSettings(tester);

    cubit.setFamily(ThemeFamily.mint);
    await tester.pumpAndSettle();
    expect(cubit.state.family, ThemeFamily.mint);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(cubit.state.family, ThemeFamily.tokyoNight);
  });
}
