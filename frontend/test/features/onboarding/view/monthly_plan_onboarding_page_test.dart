import 'package:expense_tracker/features/accounts/models/financial_account.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/loans/models/loan.dart';
import 'package:expense_tracker/features/onboarding/repositories/onboarding_setup_writer.dart';
import 'package:expense_tracker/features/onboarding/view/monthly_plan_onboarding_page.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:expense_tracker/features/recurring/models/recurring_template.dart';
import 'package:expense_tracker/features/savings/models/savings_goal.dart';
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
    this.existingRecurringTemplates = const [],
    this.existingLoans = const [],
    this.existingSavingsGoals = const [],
  });

  final List<FinancialAccount> existingAccounts;
  final MonthlyPlan? existingMonthlyPlan;
  final List<RecurringTemplate> existingRecurringTemplates;
  final List<Loan> existingLoans;
  final List<SavingsGoal> existingSavingsGoals;
  final monthlyPlans = <_SavedMonthlyPlan>[];
  final recurringTemplates = <_SavedRecurring>[];
  final updatedRecurringTemplates = <_SavedRecurring>[];
  final loans = <_SavedLoan>[];
  final updatedLoans = <_SavedLoan>[];
  final savingsGoals = <_SavedSavingsGoal>[];
  final updatedSavingsGoals = <_SavedSavingsGoal>[];
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
  Future<List<RecurringTemplate>> fetchRecurringTemplates() async {
    return existingRecurringTemplates;
  }

  @override
  Future<List<Loan>> fetchLoans() async {
    return existingLoans;
  }

  @override
  Future<List<SavingsGoal>> fetchSavingsGoals() async {
    return existingSavingsGoals;
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
  Future<void> updateRecurringTemplate({
    required String id,
    required String title,
    required String kind,
    required double amount,
    required String category,
    required String currency,
    required int dayOfMonth,
  }) async {
    updatedRecurringTemplates.add(
      _SavedRecurring(
        id: id,
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
  Future<void> updateLoan({
    required String id,
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
    updatedLoans.add(
      _SavedLoan(
        id: id,
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
  Future<void> updateSavingsGoal({
    required String id,
    required String name,
    required double targetAmount,
    required String targetCurrency,
    required String sourceCurrency,
    required double monthlyTargetAmount,
    required String startMonth,
    required String accountName,
    required String familyVisibility,
  }) async {
    updatedSavingsGoals.add(
      _SavedSavingsGoal(
        id: id,
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

  testWidgets('reopened setup preloads every setup step', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime(2026, 6, 17);
    final setupWriter = _FakeOnboardingSetupWriter(
      existingAccounts: [
        FinancialAccount(
          id: 'account-1',
          name: 'DNB current',
          institution: 'DNB',
          accountType: 'checking',
          currency: 'NOK',
          openingBalance: 12345.67,
          balanceAsOf: now,
          familyVisibility: 'private',
          notes: '',
          archived: false,
          archivedAt: null,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      existingMonthlyPlan: const MonthlyPlan(
        month: '2026-06',
        currency: 'NOK',
        totalBudget: 18548,
        totalActual: 0,
        totalRemaining: 18548,
        categories: [
          MonthlyPlanCategory(
            category: 'Rent and housing',
            budget: 8000,
            actual: 0,
            remaining: 8000,
            progress: 0,
            overBudget: false,
          ),
          MonthlyPlanCategory(
            category: 'Groceries',
            budget: 6000,
            actual: 0,
            remaining: 6000,
            progress: 0,
            overBudget: false,
          ),
          MonthlyPlanCategory(
            category: 'Transport',
            budget: 750,
            actual: 0,
            remaining: 750,
            progress: 0,
            overBudget: false,
          ),
          MonthlyPlanCategory(
            category: 'Savings',
            budget: 2500,
            actual: 0,
            remaining: 2500,
            progress: 0,
            overBudget: false,
          ),
        ],
      ),
      existingRecurringTemplates: [
        _template(
          id: 'rec-salary',
          title: 'Salary',
          kind: 'income',
          amount: 42000,
          category: 'Salary',
          day: 20,
          now: now,
        ),
        _template(
          id: 'rec-rent',
          title: 'Rent and housing',
          amount: 8000,
          category: 'Rent and housing',
          day: 3,
          now: now,
        ),
        _template(
          id: 'rec-power',
          title: 'Power',
          amount: 1200,
          category: 'Utilities',
          day: 7,
          now: now,
        ),
        _template(
          id: 'rec-netflix',
          title: 'Netflix',
          amount: 199,
          category: 'Subscriptions',
          day: 10,
          now: now,
        ),
        _template(
          id: 'rec-gym',
          title: 'Gym',
          amount: 499,
          category: 'Memberships',
          day: 5,
          now: now,
        ),
      ],
      existingLoans: [
        Loan(
          id: 'loan-1',
          name: 'VW Passat',
          lender: 'DNB',
          loanType: 'Car',
          principalAmount: 146087.67,
          openingPrincipalAmount: 146087.67,
          originalPrincipalAmount: 150534,
          emiAmount: 3733,
          currency: 'NOK',
          interestRate: 7.9,
          rateType: 'floating',
          totalEmis: 46,
          paidEmiCount: 0,
          remainingEmis: 46,
          totalPaidAmount: 0,
          prepaymentAmount: 0,
          estimatedOutstanding: 146087.67,
          dueDay: 18,
          startDate: now,
          trackingStartedAt: now,
          nextDueDate: now,
          lastPaymentAt: null,
          category: 'Loans / EMI',
          notes: '',
          archived: false,
          archivedAt: null,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      existingSavingsGoals: [
        SavingsGoal(
          id: 'goal-1',
          ownerUid: 'u1',
          ownerLabel: 'Person',
          name: 'India savings',
          goalType: 'savings_goal',
          familyVisibility: 'private',
          targetAmount: 300000,
          targetCurrency: 'INR',
          sourceCurrency: 'NOK',
          monthlyTargetAmount: 2500,
          startMonth: '2026-06',
          targetDate: null,
          maturityDate: null,
          provider: '',
          accountName: 'DNB current',
          expectedReturnRate: 0,
          totalSavedAmount: 0,
          totalSourceAmount: 0,
          remainingAmount: 300000,
          progress: 0,
          currentMonthSavedAmount: 0,
          contributionCount: 0,
          lastContributionAt: null,
          notes: '',
          archived: false,
          archivedAt: null,
          createdAt: now,
          updatedAt: now,
        ),
      ],
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
    await _advance(tester);
    expect(find.text('42000'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    await _advance(tester);
    expect(find.text('8000'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await _advance(tester);
    expect(find.text('VW Passat'), findsOneWidget);
    expect(find.text('DNB'), findsOneWidget);
    expect(find.text('146087.67'), findsOneWidget);
    expect(find.text('3733'), findsOneWidget);
    await _advance(tester);
    expect(find.text('6000'), findsOneWidget);
    await _advance(tester);
    expect(find.text('Power'), findsOneWidget);
    expect(find.text('Netflix'), findsAtLeastNWidgets(1));
    expect(find.text('Gym'), findsAtLeastNWidgets(1));
    await _advance(tester);
    expect(find.text('750'), findsOneWidget);
    await _advance(tester);
    expect(find.text('India savings'), findsOneWidget);
    expect(find.text('2500'), findsOneWidget);
    expect(find.text('300000'), findsOneWidget);
    expect(find.text('INR'), findsOneWidget);
    await _advance(tester);

    await tester.tap(find.byKey(const ValueKey('onboarding-complete-setup')));
    await tester.pumpAndSettle();

    expect(setupWriter.accounts, isEmpty);
    expect(setupWriter.updatedAccounts.single.id, 'account-1');
    expect(setupWriter.recurringTemplates, isEmpty);
    expect(
      setupWriter.updatedRecurringTemplates.map((item) => item.id),
      containsAll(<String>[
        'rec-salary',
        'rec-rent',
        'rec-power',
        'rec-netflix',
        'rec-gym',
      ]),
    );
    expect(setupWriter.loans, isEmpty);
    expect(setupWriter.updatedLoans.single.id, 'loan-1');
    expect(setupWriter.savingsGoals, isEmpty);
    expect(setupWriter.updatedSavingsGoals.single.id, 'goal-1');
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

RecurringTemplate _template({
  required String id,
  required String title,
  String kind = 'expense',
  required double amount,
  required String category,
  required int day,
  required DateTime now,
}) {
  return RecurringTemplate(
    id: id,
    title: title,
    kind: kind,
    amount: amount,
    currency: 'NOK',
    category: category,
    frequency: 'monthly',
    dayOfMonth: day,
    startDate: now,
    nextDueDate: now,
    active: true,
  );
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
    this.id,
    required this.title,
    required this.kind,
    required this.amount,
    required this.category,
    required this.currency,
    required this.dayOfMonth,
  });

  final String? id;
  final String title;
  final String kind;
  final double amount;
  final String category;
  final String currency;
  final int dayOfMonth;
}

class _SavedLoan {
  const _SavedLoan({
    this.id,
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

  final String? id;
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
    this.id,
    required this.name,
    required this.targetAmount,
    required this.targetCurrency,
    required this.sourceCurrency,
    required this.monthlyTargetAmount,
    required this.startMonth,
    required this.accountName,
    required this.familyVisibility,
  });

  final String? id;
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
