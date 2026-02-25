import 'package:expense_tracker/app/view/home_shell_page.dart';
import 'package:expense_tracker/core/theme/app_theme.dart';
import 'package:expense_tracker/features/theme/cubit/theme_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ExpenseTrackerAppView extends StatelessWidget {
  const ExpenseTrackerAppView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ThemeCubit(),
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, state) {
          final theme = AppThemeFactory.build(state);
          final mode =
              (state.variant == ThemeVariant.dark ||
                  state.variant == ThemeVariant.custom)
              ? ThemeMode.dark
              : ThemeMode.light;
          return MaterialApp(
            title: 'Expense Tracker',
            debugShowCheckedModeBanner: false,
            theme: theme,
            darkTheme: theme,
            themeMode: mode,
            home: const HomeShellPage(),
          );
        },
      ),
    );
  }
}
