import 'package:expense_tracker/app/routes/app_routes.dart';
import 'package:expense_tracker/app/view/home_shell_page.dart';
import 'package:expense_tracker/core/theme/app_theme.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/auth/cubit/auth_state.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/auth/view/login_page.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/friends/view/friends_page.dart';
import 'package:expense_tracker/features/groups/view/groups_page.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:expense_tracker/features/profile/view/account_edit_route_page.dart';
import 'package:expense_tracker/features/theme/cubit/theme_cubit.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:flutter/foundation.dart';
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
            repository: authRepository ?? ApiAuthRepository(),
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
            initialRoute: AppRoutes.home,
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
    final page = _AuthGuardedRoute(
      routeName: routeName,
      profileRepository: profileRepository,
    );
    if (kIsWeb) {
      return PageRouteBuilder<void>(
        settings: RouteSettings(name: routeName),
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );
    }

    return MaterialPageRoute<void>(
      settings: RouteSettings(name: routeName),
      builder: (_) => page,
    );
  }

  String _normalizeRoute(String? name) {
    switch (name) {
      case AppRoutes.root:
      case AppRoutes.home:
      case AppRoutes.overview:
      case AppRoutes.friends:
      case AppRoutes.family:
      case AppRoutes.groups:
      case AppRoutes.activity:
      case AppRoutes.account:
      case AppRoutes.accountEdit:
        return name ?? AppRoutes.home;
      default:
        return AppRoutes.home;
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
        final user = authState.user;
        if (user == null) {
          return const LoginPage();
        }

        final routed = switch (routeName) {
          AppRoutes.home => const HomeShellPage(initialIndex: 0),
          AppRoutes.overview => const HomeShellPage(initialIndex: 0),
          AppRoutes.friends => const FriendsPage(),
          AppRoutes.family => const HomeShellPage(initialIndex: 1),
          AppRoutes.groups => const GroupsPage(),
          AppRoutes.activity => const HomeShellPage(initialIndex: 2),
          AppRoutes.account => const HomeShellPage(initialIndex: 3),
          AppRoutes.accountEdit => AccountEditRoutePage(
            profileRepository: profileRepository,
          ),
          _ => const HomeShellPage(initialIndex: 0),
        };

        return RepositoryProvider(
          create: (_) => ExpenseRepository(),
          dispose: (repository) => repository.dispose(),
          child: BlocProvider(
            create: (context) =>
                ExpensesBloc(repository: context.read<ExpenseRepository>())
                  ..add(const LoadExpenses()),
            child: routed,
          ),
        );
      },
    );
  }
}
