import 'package:expense_tracker/features/accounts/models/financial_account.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/onboarding/repositories/onboarding_setup_writer.dart';
import 'package:expense_tracker/features/onboarding/view/monthly_plan_onboarding_page.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
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

class _FakeOnboardingSetupWriter implements OnboardingSetupWriter {
  _FakeOnboardingSetupWriter({
    this.existingAccounts = const [],
    this.existingMonthlyPlan,
  });

  final List<FinancialAccount> existingAccounts;
  final MonthlyPlan? existingMonthlyPlan;
  final monthlyPlans = <_SavedMonthlyPlan>[];
  final recurringTemplates = <_SavedRecurring>[];
  final loans = <_SavedLoan>[];
  final savingsGoals = <_SavedSavingsGoal>[];
  final accounts = <_SavedAccount>[];
  final updatedAccounts = <_SavedAccount>[];
  var disposed = false;

  @override
  Future<List<FinancialAccount>> fetchFinancialAccounts() async {
    return existingAccounts;
  }

  @override
  Future<MonthlyPlan> fetchMonthlyPlan({required String month}) async {
    return existingMonthlyPlan ??
        MonthlyPlan(
          month: month,
          currency: 'NOK',
          totalBudget: 0,
          totalActual: 0,
          totalRemaining: 0,
          categories: const [],
        );
  }

  @override
  Future<void> saveMonthlyPlan({
    required String month,
    required String currency,
    required Map<String, double> budgets,
  }) async {
    monthlyPlans.add(
      _SavedMonthlyPlan(month: month, currency: currency, budgets: budgets),
    );
  }

  @override
  Future<void> createRecurringTemplate({
    required String title,
    required String kind,
    required double amount,
    required String category,
    required String currency,
    required int dayOfMonth,
  }) async {
    recurringTemplates.add(
      _SavedRecurring(
        title: title,
        kind: kind,
        amount: amount,
        category: category,
        currency: currency,
        dayOfMonth: dayOfMonth,
      ),
    );
  }

  @override
  Future<void> createLoan({
    required String name,
    required String lender,
    required String loanType,
    required double principalAmount,
    required double emiAmount,
    required String currency,
    required double interestRate,
    required String rateType,
    required int remainingEmis,
    required int dueDay,
  }) async {
    loans.add(
      _SavedLoan(
        name: name,
        lender: lender,
        loanType: loanType,
        principalAmount: principalAmount,
        emiAmount: emiAmount,
        currency: currency,
        interestRate: interestRate,
        rateType: rateType,
        remainingEmis: remainingEmis,
        dueDay: dueDay,
      ),
    );
  }

  @override
  Future<void> createSavingsGoal({
    required String name,
    required double targetAmount,
    required String targetCurrency,
    required String sourceCurrency,
    required double monthlyTargetAmount,
    required String startMonth,
    required String accountName,
    required String familyVisibility,
  }) async {
    savingsGoals.add(
      _SavedSavingsGoal(
        name: name,
        targetAmount: targetAmount,
        targetCurrency: targetCurrency,
        sourceCurrency: sourceCurrency,
        monthlyTargetAmount: monthlyTargetAmount,
        startMonth: startMonth,
        accountName: accountName,
        familyVisibility: familyVisibility,
      ),
    );
  }

  @override
  Future<void> createFinancialAccount({
    required String name,
    required String institution,
    required String accountType,
    required String currency,
    required double openingBalance,
  }) async {
    accounts.add(
      _SavedAccount(
        name: name,
        institution: institution,
        accountType: accountType,
        currency: currency,
        openingBalance: openingBalance,
      ),
    );
  }

  @override
  Future<void> updateFinancialAccount({
    required String id,
    required String name,
    required String institution,
    required String accountType,
    required String currency,
    required double openingBalance,
  }) async {
    updatedAccounts.add(
      _SavedAccount(
        id: id,
        name: name,
        institution: institution,
        accountType: accountType,
        currency: currency,
        openingBalance: openingBalance,
      ),
    );
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  testWidgets(
    'guided setup saves plan, accounts, recurring, loan, and savings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final authCubit = _authCubit();
      final setupWriter = _FakeOnboardingSetupWriter();

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: authCubit,
            child: MonthlyPlanOnboardingPage(setupWriter: setupWriter),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Currency'), findsOneWidget);
      await _advance(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Account name'),
        'DNB savings',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Bank or provider'),
        'DNB',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Balance now'),
        '10000',
      );
      await tester.tap(find.text('Savings'));
      await tester.pumpAndSettle();
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Checking'), findsNothing);
      await tester.tap(find.text('Current'));
      await tester.pumpAndSettle();
      await _advance(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Monthly salary'),
        '42000',
      );
      await _advance(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Rent or housing payment'),
        '12000',
      );
      await _advance(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Remaining principal'),
        '146,087.67',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Monthly EMI'),
        '3733',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Interest rate'),
        '7.9',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Months left'),
        '46',
      );
      await _advance(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Monthly grocery budget'),
        '5000',
      );
      await _advance(tester);

      await tester.enterText(
        find.byKey(const ValueKey('utilities-0-name')),
        'Power',
      );
      await tester.enterText(
        find.byKey(const ValueKey('utilities-0-amount')),
        '1200',
      );
      await tester.enterText(
        find.byKey(const ValueKey('subscriptions-0-name')),
        'Netflix',
      );
      await tester.enterText(
        find.byKey(const ValueKey('subscriptions-0-amount')),
        '199',
      );
      await tester.tap(find.byKey(const ValueKey('subscriptions-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('subscriptions-1-name')),
        'Spotify',
      );
      await tester.enterText(
        find.byKey(const ValueKey('subscriptions-1-amount')),
        '200',
      );
      await tester.enterText(
        find.byKey(const ValueKey('memberships-0-name')),
        'Gym',
      );
      await tester.enterText(
        find.byKey(const ValueKey('memberships-0-amount')),
        '499',
      );
      await _advance(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Monthly transport budget'),
        '750',
      );
      await _advance(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Monthly savings'),
        '2500',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Target amount'),
        '300000',
      );
      await _advance(tester);

      expect(find.text('Review'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('onboarding-complete-setup')));
      await tester.pump();
      await tester.pump();

      expect(authCubit.state.user?.onboardingCompleted, isTrue);
      expect(setupWriter.accounts.single.name, 'DNB savings');
      expect(setupWriter.accounts.single.accountType, 'checking');
      expect(setupWriter.accounts.single.openingBalance, 10000);
      expect(
        setupWriter.recurringTemplates.map((item) => item.title),
        contains('Salary'),
      );
      expect(
        setupWriter.recurringTemplates.map((item) => item.title),
        contains('Rent and housing'),
      );
      expect(setupWriter.loans.single.principalAmount, 146087.67);
      expect(setupWriter.loans.single.rateType, 'floating');
      expect(setupWriter.savingsGoals.single.accountName, 'DNB savings');
      expect(setupWriter.savingsGoals.single.familyVisibility, 'private');
      expect(
        setupWriter.recurringTemplates.map((item) => item.title),
        containsAll(<String>['Power', 'Netflix', 'Spotify', 'Gym']),
      );
      expect(setupWriter.monthlyPlans.single.currency, 'NOK');
      expect(
        setupWriter.monthlyPlans.single.budgets,
        containsPair('Groceries', 5000),
      );
      expect(
        setupWriter.monthlyPlans.single.budgets,
        containsPair('Utilities', 1200),
      );
      expect(
        setupWriter.monthlyPlans.single.budgets,
        containsPair('Subscriptions', 399),
      );
      expect(
        setupWriter.monthlyPlans.single.budgets,
        containsPair('Memberships', 499),
      );
      expect(
        setupWriter.monthlyPlans.single.budgets,
        containsPair('Loans / EMI', 3733),
      );
      expect(
        setupWriter.monthlyPlans.single.budgets,
        containsPair('Savings', 2500),
      );
    },
  );

  testWidgets('can complete setup early from the bills step', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authCubit = _authCubit();
    final setupWriter = _FakeOnboardingSetupWriter();

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: authCubit,
          child: MonthlyPlanOnboardingPage(setupWriter: setupWriter),
        ),
      ),
    );
    await tester.pump();

    await _advance(tester);
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();

    expect(find.text('Bills and subscriptions'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('subscriptions-0-name')),
      'YouTube Premium',
    );
    await tester.enterText(
      find.byKey(const ValueKey('subscriptions-0-amount')),
      '129',
    );

    await tester.ensureVisible(find.text('Complete setup'));
    await tester.tap(find.text('Complete setup'));
    await tester.pump();
    await tester.pump();

    expect(authCubit.state.user?.onboardingCompleted, isTrue);
    expect(setupWriter.recurringTemplates.single.title, 'YouTube Premium');
    expect(
      setupWriter.monthlyPlans.single.budgets,
      containsPair('Subscriptions', 129),
    );
  });

  testWidgets('can skip an individual onboarding step', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: _authCubit(),
          child: MonthlyPlanOnboardingPage(
            setupWriter: _FakeOnboardingSetupWriter(),
          ),
        ),
      ),
    );
    await tester.pump();

    await _advance(tester);
    expect(find.text('Bank accounts'), findsOneWidget);
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    expect(find.text('Salary'), findsOneWidget);
  });

  testWidgets('reopened setup preloads existing bank accounts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final setupWriter = _FakeOnboardingSetupWriter(
      existingAccounts: [
        FinancialAccount(
          id: 'account-1',
          name: 'DNB current',
          institution: 'DNB',
          accountType: 'checking',
          currency: 'NOK',
          openingBalance: 12345.67,
          balanceAsOf: DateTime(2026, 6, 16),
          familyVisibility: 'private',
          notes: '',
          archived: false,
          archivedAt: null,
          createdAt: DateTime(2026, 6, 16),
          updatedAt: DateTime(2026, 6, 16),
        ),
      ],
      existingMonthlyPlan: const MonthlyPlan(
        month: '2026-06',
        currency: 'NOK',
        totalBudget: 8000,
        totalActual: 0,
        totalRemaining: 8000,
        categories: [
          MonthlyPlanCategory(
            category: 'Rent and housing',
            budget: 8000,
            actual: 0,
            remaining: 8000,
            progress: 0,
            overBudget: false,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: _authCubit(),
          child: MonthlyPlanOnboardingPage(
            setupWriter: setupWriter,
            completeOnFinish: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _advance(tester);

    expect(find.text('DNB current'), findsOneWidget);
    expect(find.text('DNB'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);

    await _advance(tester);
    await _advance(tester);
    expect(find.text('8000'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-complete-setup')));
    await tester.pumpAndSettle();

    expect(setupWriter.accounts, isEmpty);
    expect(setupWriter.updatedAccounts.single.id, 'account-1');
    expect(setupWriter.updatedAccounts.single.name, 'DNB current');
  });
}

AuthCubit _authCubit() {
  const user = AuthUser(
    uid: 'u1',
    email: 'person@example.com',
    displayName: 'Person',
  );
  return AuthCubit(
    repository: _FakeAuthRepository(user),
    userProfileRepository: _FakeProfileRepository(),
  );
}

Future<void> _advance(WidgetTester tester) async {
  final next = find.text('Next');
  final review = find.text('Review');
  if (review.evaluate().isNotEmpty) {
    await tester.tap(review);
  } else {
    await tester.tap(next);
  }
  await tester.pumpAndSettle();
}

class _SavedMonthlyPlan {
  const _SavedMonthlyPlan({
    required this.month,
    required this.currency,
    required this.budgets,
  });

  final String month;
  final String currency;
  final Map<String, double> budgets;
}

class _SavedRecurring {
  const _SavedRecurring({
    required this.title,
    required this.kind,
    required this.amount,
    required this.category,
    required this.currency,
    required this.dayOfMonth,
  });

  final String title;
  final String kind;
  final double amount;
  final String category;
  final String currency;
  final int dayOfMonth;
}

class _SavedLoan {
  const _SavedLoan({
    required this.name,
    required this.lender,
    required this.loanType,
    required this.principalAmount,
    required this.emiAmount,
    required this.currency,
    required this.interestRate,
    required this.rateType,
    required this.remainingEmis,
    required this.dueDay,
  });

  final String name;
  final String lender;
  final String loanType;
  final double principalAmount;
  final double emiAmount;
  final String currency;
  final double interestRate;
  final String rateType;
  final int remainingEmis;
  final int dueDay;
}

class _SavedSavingsGoal {
  const _SavedSavingsGoal({
    required this.name,
    required this.targetAmount,
    required this.targetCurrency,
    required this.sourceCurrency,
    required this.monthlyTargetAmount,
    required this.startMonth,
    required this.accountName,
    required this.familyVisibility,
  });

  final String name;
  final double targetAmount;
  final String targetCurrency;
  final String sourceCurrency;
  final double monthlyTargetAmount;
  final String startMonth;
  final String accountName;
  final String familyVisibility;
}

class _SavedAccount {
  const _SavedAccount({
    this.id,
    required this.name,
    required this.institution,
    required this.accountType,
    required this.currency,
    required this.openingBalance,
  });

  final String? id;
  final String name;
  final String institution;
  final String accountType;
  final String currency;
  final double openingBalance;
}
