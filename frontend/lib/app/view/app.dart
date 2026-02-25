import 'package:expense_tracker/app/routes/app_routes.dart';
import 'package:expense_tracker/app/view/home_shell_page.dart';
import 'package:expense_tracker/core/theme/app_theme.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/auth/cubit/auth_state.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/auth/view/login_page.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:expense_tracker/features/profile/view/account_edit_route_page.dart';
import 'package:expense_tracker/features/theme/cubit/theme_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ExpenseTrackerAppView extends StatelessWidget {
  const ExpenseTrackerAppView({this.authRepository, super.key});

  final AuthRepository? authRepository;

  @override
  Widget build(BuildContext context) {
    final profileRepository = UserProfileRepository();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeCubit()),
        BlocProvider(
          create: (_) => AuthCubit(
            repository: authRepository ?? FirebaseAuthRepository(),
            userProfileRepository: profileRepository,
          ),
        ),
      ],
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
            initialRoute: AppRoutes.overview,
            onGenerateRoute: (settings) => _onGenerateRoute(
              settings: settings,
              profileRepository: profileRepository,
            ),
          );
        },
      ),
    );
  }

  Route<dynamic> _onGenerateRoute({
    required RouteSettings settings,
    required UserProfileRepository profileRepository,
  }) {
    final routeName = _normalizeRoute(settings.name);
    return MaterialPageRoute<void>(
      settings: RouteSettings(name: routeName),
      builder: (_) => _AuthGuardedRoute(
        routeName: routeName,
        profileRepository: profileRepository,
      ),
    );
  }

  String _normalizeRoute(String? name) {
    switch (name) {
      case AppRoutes.root:
      case AppRoutes.overview:
      case AppRoutes.friends:
      case AppRoutes.groups:
      case AppRoutes.activity:
      case AppRoutes.account:
      case AppRoutes.accountEdit:
        return name ?? AppRoutes.overview;
      default:
        return AppRoutes.overview;
    }
  }
}

class _AuthGuardedRoute extends StatelessWidget {
  const _AuthGuardedRoute({
    required this.routeName,
    required this.profileRepository,
  });

  final String routeName;
  final UserProfileRepository profileRepository;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, authState) {
        if (authState.status != AuthStatus.authenticated) {
          return const LoginPage();
        }

        switch (routeName) {
          case AppRoutes.overview:
            return const HomeShellPage(initialIndex: 0);
          case AppRoutes.friends:
            return const HomeShellPage(initialIndex: 1);
          case AppRoutes.groups:
            return const HomeShellPage(initialIndex: 2);
          case AppRoutes.activity:
            return const HomeShellPage(initialIndex: 3);
          case AppRoutes.account:
            return const HomeShellPage(initialIndex: 4);
          case AppRoutes.accountEdit:
            return AccountEditRoutePage(profileRepository: profileRepository);
          case AppRoutes.root:
          default:
            return const HomeShellPage(initialIndex: 0);
        }
      },
    );
  }
}
