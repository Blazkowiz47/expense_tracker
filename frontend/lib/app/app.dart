import 'package:expense_tracker/app/view/app.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:flutter/widgets.dart';

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({
    this.authRepository,
    this.dashboardRepository,
    this.expensesRepository,
    this.profileRepository,
    super.key,
  });

  final AuthRepository? authRepository;
  final DashboardSnapshotRepository? dashboardRepository;
  final ExpenseRepository? expensesRepository;
  final UserProfileRepository? profileRepository;

  @override
  Widget build(BuildContext context) {
    return ExpenseTrackerAppView(
      authRepository: authRepository,
      dashboardRepository: dashboardRepository,
      expensesRepository: expensesRepository,
      profileRepository: profileRepository,
    );
  }
}
