import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/onboarding/view/monthly_plan_onboarding_page.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.user);

  final AuthUser user;

  @override
  Stream<AuthUser?> authStateChanges() => Stream<AuthUser?>.value(user);

  @override
  Future<void> login({required String email, required String password}) async {}

  @override
  Future<void> loginWithGoogle() async {}

  @override
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class _FakeProfileRepository extends UserProfileRepository {
  @override
  Future<void> ensureUserDocument(AuthUser user) async {}

  @override
  Future<AuthUser> updateOnboardingCompleted({
    required AuthUser user,
    required bool completed,
  }) async {
    return user.copyWith(onboardingCompleted: completed);
  }
}

class _FakeMonthlyPlanRepository implements MonthlyPlanRepository {
  String? savedMonth;
  String? savedCurrency;
  Map<String, double>? savedBudgets;

  @override
  Future<MonthlyPlan> savePlan({
    required String month,
    String? groupId,
    required String currency,
    required Map<String, double> budgets,
  }) async {
    savedMonth = month;
    savedCurrency = currency;
    savedBudgets = budgets;
    final total = budgets.values.fold<double>(0, (sum, value) => sum + value);
    return MonthlyPlan(
      month: month,
      currency: currency,
      totalBudget: total,
      totalActual: 0,
      totalRemaining: total,
      categories: const [],
    );
  }

  @override
  Future<MonthlyPlan> fetchPlan({required String month, String? groupId}) {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}

void main() {
  testWidgets('saves monthly plan and completes onboarding', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const user = AuthUser(
      uid: 'u1',
      email: 'person@example.com',
      displayName: 'Person',
    );
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(user),
      userProfileRepository: _FakeProfileRepository(),
    );
    final planRepository = _FakeMonthlyPlanRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: authCubit,
          child: MonthlyPlanOnboardingPage(repository: planRepository),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextField, 'Groceries'), '5000');
    await tester.enterText(find.widgetWithText(TextField, 'Savings'), '2000');
    await tester.tap(find.text('Save monthly plan'));
    await tester.pump();
    await tester.pump();

    expect(planRepository.savedCurrency, 'NOK');
    expect(planRepository.savedBudgets, containsPair('Groceries', 5000));
    expect(planRepository.savedBudgets, containsPair('Savings', 2000));
    expect(authCubit.state.user?.onboardingCompleted, isTrue);
  });
}
