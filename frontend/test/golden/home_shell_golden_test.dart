import 'package:expense_tracker/app/view/home_shell_page.dart';
import 'package:expense_tracker/core/theme/app_theme.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:expense_tracker/features/theme/cubit/theme_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    required Size size,
    required ThemeState themeState,
  }) async {
    final cubit = ThemeCubit()
      ..setFamily(themeState.family)
      ..setVariant(themeState.variant)
      ..setCustomAccent(themeState.customAccent);

    addTearDown(cubit.close);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: BlocProvider.value(
          value: cubit,
          child: BlocBuilder<ThemeCubit, ThemeState>(
            builder: (context, state) {
              final theme = AppThemeFactory.build(state);
              return MaterialApp(
                theme: theme,
                darkTheme: theme,
                home: const HomeShellPage(
                  repository: MockDashboardSnapshotRepository(),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('home shell mobile splitwise light golden', (tester) async {
    await pumpShell(
      tester,
      size: const Size(430, 932),
      themeState: const ThemeState(
        family: ThemeFamily.splitwise,
        variant: ThemeVariant.light,
      ),
    );
    await expectLater(
      find.byType(HomeShellPage),
      matchesGoldenFile('goldens/home_shell_mobile_splitwise_light.png'),
    );
  });

  testWidgets('home shell mobile tokyo dark golden', (tester) async {
    await pumpShell(
      tester,
      size: const Size(430, 932),
      themeState: const ThemeState(
        family: ThemeFamily.tokyoNight,
        variant: ThemeVariant.dark,
      ),
    );
    await expectLater(
      find.byType(HomeShellPage),
      matchesGoldenFile('goldens/home_shell_mobile_tokyo_dark.png'),
    );
  });

  testWidgets('home shell mobile tokyo high contrast golden', (tester) async {
    await pumpShell(
      tester,
      size: const Size(430, 932),
      themeState: const ThemeState(
        family: ThemeFamily.tokyoNight,
        variant: ThemeVariant.highContrast,
      ),
    );
    await expectLater(
      find.byType(HomeShellPage),
      matchesGoldenFile('goldens/home_shell_mobile_tokyo_high_contrast.png'),
    );
  });

  testWidgets('home shell mobile tokyo custom golden', (tester) async {
    await pumpShell(
      tester,
      size: const Size(430, 932),
      themeState: const ThemeState(
        family: ThemeFamily.tokyoNight,
        variant: ThemeVariant.custom,
        customAccentValue: 0xFFFF6B6B,
      ),
    );
    await expectLater(
      find.byType(HomeShellPage),
      matchesGoldenFile('goldens/home_shell_mobile_tokyo_custom.png'),
    );
  });

  testWidgets('home shell desktop splitwise light golden', (tester) async {
    await pumpShell(
      tester,
      size: const Size(1366, 900),
      themeState: const ThemeState(
        family: ThemeFamily.splitwise,
        variant: ThemeVariant.light,
      ),
    );
    await expectLater(
      find.byType(HomeShellPage),
      matchesGoldenFile('goldens/home_shell_desktop_splitwise_light.png'),
    );
  });

  testWidgets('home shell desktop tokyo dark golden', (tester) async {
    await pumpShell(
      tester,
      size: const Size(1366, 900),
      themeState: const ThemeState(
        family: ThemeFamily.tokyoNight,
        variant: ThemeVariant.dark,
      ),
    );
    await expectLater(
      find.byType(HomeShellPage),
      matchesGoldenFile('goldens/home_shell_desktop_tokyo_dark.png'),
    );
  });

  testWidgets('home shell desktop tokyo high contrast golden', (tester) async {
    await pumpShell(
      tester,
      size: const Size(1366, 900),
      themeState: const ThemeState(
        family: ThemeFamily.tokyoNight,
        variant: ThemeVariant.highContrast,
      ),
    );
    await expectLater(
      find.byType(HomeShellPage),
      matchesGoldenFile('goldens/home_shell_desktop_tokyo_high_contrast.png'),
    );
  });

  testWidgets('home shell desktop tokyo custom golden', (tester) async {
    await pumpShell(
      tester,
      size: const Size(1366, 900),
      themeState: const ThemeState(
        family: ThemeFamily.tokyoNight,
        variant: ThemeVariant.custom,
        customAccentValue: 0xFF9D7CFF,
      ),
    );
    await expectLater(
      find.byType(HomeShellPage),
      matchesGoldenFile('goldens/home_shell_desktop_tokyo_custom.png'),
    );
  });

  testWidgets(
    'home shell iOS mobile tokyo dark golden',
    (tester) async {
      await pumpShell(
        tester,
        size: const Size(430, 932),
        themeState: const ThemeState(
          family: ThemeFamily.tokyoNight,
          variant: ThemeVariant.dark,
        ),
      );
      await expectLater(
        find.byType(HomeShellPage),
        matchesGoldenFile('goldens/home_shell_ios_mobile_tokyo_dark.png'),
      );
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );
}
