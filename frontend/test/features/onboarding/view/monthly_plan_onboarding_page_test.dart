import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/onboarding/repositories/onboarding_setup_writer.dart';
import 'package:expense_tracker/features/onboarding/view/monthly_plan_onboarding_page.dart';
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
  final monthlyPlans = <_SavedMonthlyPlan>[];
  final recurringTemplates = <_SavedRecurring>[];
  final loans = <_SavedLoan>[];
  final savingsGoals = <_SavedSavingsGoal>[];
  final accounts = <_SavedAccount>[];
  var disposed = false;

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
      await _next(tester);

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
      await _next(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Monthly salary'),
        '42000',
      );
      await _next(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Rent or housing payment'),
        '12000',
      );
      await _next(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Remaining principal'),
        '146087.67',
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
      await _next(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Monthly grocery budget'),
        '5000',
      );
      await _next(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Utilities'),
        '1200',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Subscriptions'),
        '399',
      );
      await _next(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Monthly transport budget'),
        '750',
      );
      await _next(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Monthly savings'),
        '2500',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Target amount'),
        '300000',
      );
      await _next(tester);

      expect(find.text('Review'), findsOneWidget);
      await tester.tap(find.text('Finish setup'));
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
      expect(setupWriter.monthlyPlans.single.currency, 'NOK');
      expect(
        setupWriter.monthlyPlans.single.budgets,
        containsPair('Groceries', 5000),
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

    await _next(tester);
    expect(find.text('Bank accounts'), findsOneWidget);
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    expect(find.text('Salary'), findsOneWidget);
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

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
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
    required this.name,
    required this.institution,
    required this.accountType,
    required this.currency,
    required this.openingBalance,
  });

  final String name;
  final String institution;
  final String accountType;
  final String currency;
  final double openingBalance;
}
