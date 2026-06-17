import 'package:expense_tracker/features/accounts/models/financial_account.dart';
import 'package:expense_tracker/features/accounts/repositories/api_accounts_repository.dart';
import 'package:expense_tracker/features/loans/models/loan.dart';
import 'package:expense_tracker/features/loans/repositories/api_loans_repository.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:expense_tracker/features/recurring/models/recurring_template.dart';
import 'package:expense_tracker/features/recurring/repositories/api_recurring_repository.dart';
import 'package:expense_tracker/features/savings/models/savings_goal.dart';
import 'package:expense_tracker/features/savings/repositories/api_savings_repository.dart';
import 'package:http/http.dart' as http;

abstract class OnboardingSetupWriter {
  Future<List<FinancialAccount>> fetchFinancialAccounts();

  Future<MonthlyPlan> fetchMonthlyPlan({required String month});

  Future<List<RecurringTemplate>> fetchRecurringTemplates();

  Future<List<Loan>> fetchLoans();

  Future<List<SavingsGoal>> fetchSavingsGoals();

  Future<void> saveMonthlyPlan({
    required String month,
    required String currency,
    required Map<String, double> budgets,
    double? income,
  });

  Future<void> createRecurringTemplate({
    required String title,
    required String kind,
    required double amount,
    required String category,
    required String currency,
    required String frequency,
    required int dayOfMonth,
  });

  Future<void> updateRecurringTemplate({
    required String id,
    required String title,
    required String kind,
    required double amount,
    required String category,
    required String currency,
    required String frequency,
    required int dayOfMonth,
  });

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
  });

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
  });

  Future<void> createSavingsGoal({
    required String name,
    required double targetAmount,
    required String targetCurrency,
    required String sourceCurrency,
    required double monthlyTargetAmount,
    required String startMonth,
    required String accountName,
    required String familyVisibility,
  });

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
  });

  Future<void> createFinancialAccount({
    required String name,
    required String institution,
    required String accountType,
    required String currency,
    required double openingBalance,
  });

  Future<void> updateFinancialAccount({
    required String id,
    required String name,
    required String institution,
    required String accountType,
    required String currency,
    required double openingBalance,
  });

  void dispose();
}

class ApiOnboardingSetupWriter implements OnboardingSetupWriter {
  factory ApiOnboardingSetupWriter({
    MonthlyPlanRepository? monthlyPlanRepository,
    ApiRecurringRepository? recurringRepository,
    ApiLoansRepository? loansRepository,
    ApiSavingsRepository? savingsRepository,
    ApiAccountsRepository? accountsRepository,
    http.Client? client,
  }) {
    final sharedClient = client ?? http.Client();
    return ApiOnboardingSetupWriter._(
      client: sharedClient,
      ownsClient: client == null,
      monthlyPlanRepository:
          monthlyPlanRepository ?? MonthlyPlanRepository(client: sharedClient),
      recurringRepository:
          recurringRepository ?? ApiRecurringRepository(client: sharedClient),
      loansRepository:
          loansRepository ?? ApiLoansRepository(client: sharedClient),
      savingsRepository:
          savingsRepository ?? ApiSavingsRepository(client: sharedClient),
      accountsRepository:
          accountsRepository ?? ApiAccountsRepository(client: sharedClient),
    );
  }

  ApiOnboardingSetupWriter._({
    required http.Client client,
    required bool ownsClient,
    required MonthlyPlanRepository monthlyPlanRepository,
    required ApiRecurringRepository recurringRepository,
    required ApiLoansRepository loansRepository,
    required ApiSavingsRepository savingsRepository,
    required ApiAccountsRepository accountsRepository,
  }) : _client = client,
       _ownsClient = ownsClient,
       _monthlyPlanRepository = monthlyPlanRepository,
       _recurringRepository = recurringRepository,
       _loansRepository = loansRepository,
       _savingsRepository = savingsRepository,
       _accountsRepository = accountsRepository;

  final http.Client _client;
  final bool _ownsClient;
  final MonthlyPlanRepository _monthlyPlanRepository;
  final ApiRecurringRepository _recurringRepository;
  final ApiLoansRepository _loansRepository;
  final ApiSavingsRepository _savingsRepository;
  final ApiAccountsRepository _accountsRepository;

  @override
  Future<List<FinancialAccount>> fetchFinancialAccounts() {
    return _accountsRepository.fetchAccounts();
  }

  @override
  Future<MonthlyPlan> fetchMonthlyPlan({required String month}) {
    return _monthlyPlanRepository.fetchPlan(month: month);
  }

  @override
  Future<List<RecurringTemplate>> fetchRecurringTemplates() {
    return _recurringRepository.fetchTemplates();
  }

  @override
  Future<List<Loan>> fetchLoans() {
    return _loansRepository.fetchLoans();
  }

  @override
  Future<List<SavingsGoal>> fetchSavingsGoals() {
    return _savingsRepository.fetchGoals();
  }

  @override
  Future<void> saveMonthlyPlan({
    required String month,
    required String currency,
    required Map<String, double> budgets,
    double? income,
  }) async {
    await _monthlyPlanRepository.savePlan(
      month: month,
      currency: currency,
      budgets: budgets,
      income: income,
    );
  }

  @override
  Future<void> createRecurringTemplate({
    required String title,
    required String kind,
    required double amount,
    required String category,
    required String currency,
    required String frequency,
    required int dayOfMonth,
  }) async {
    await _recurringRepository.createTemplate(
      title: title,
      kind: kind,
      amount: amount,
      category: category,
      currency: currency,
      frequency: frequency,
      dayOfMonth: dayOfMonth,
      startDate: DateTime.now(),
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
    required String frequency,
    required int dayOfMonth,
  }) async {
    await _recurringRepository.updateTemplate(
      id: id,
      title: title,
      kind: kind,
      amount: amount,
      category: category,
      currency: currency,
      frequency: frequency,
      dayOfMonth: dayOfMonth,
      startDate: DateTime.now(),
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
    await _loansRepository.createLoan(
      name: name,
      lender: lender,
      loanType: loanType,
      principalAmount: principalAmount,
      emiAmount: emiAmount,
      currency: currency,
      interestRate: interestRate,
      rateType: rateType,
      totalEmis: remainingEmis,
      dueDay: dueDay,
      startDate: DateTime.now(),
      category: 'Loans / EMI',
      notes: 'Added during onboarding.',
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
    await _loansRepository.updateLoan(
      id: id,
      name: name,
      lender: lender,
      loanType: loanType,
      principalAmount: principalAmount,
      emiAmount: emiAmount,
      currency: currency,
      interestRate: interestRate,
      rateType: rateType,
      totalEmis: remainingEmis,
      dueDay: dueDay,
      startDate: DateTime.now(),
      category: 'Loans / EMI',
      notes: 'Updated during setup.',
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
    await _savingsRepository.createGoal(
      name: name,
      targetAmount: targetAmount,
      targetCurrency: targetCurrency,
      sourceCurrency: sourceCurrency,
      monthlyTargetAmount: monthlyTargetAmount,
      startMonth: startMonth,
      accountName: accountName,
      familyVisibility: familyVisibility,
      notes: 'Added during onboarding.',
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
    await _savingsRepository.updateGoal(
      id: id,
      name: name,
      targetAmount: targetAmount,
      targetCurrency: targetCurrency,
      sourceCurrency: sourceCurrency,
      monthlyTargetAmount: monthlyTargetAmount,
      startMonth: startMonth,
      accountName: accountName,
      familyVisibility: familyVisibility,
      notes: 'Updated during setup.',
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
    await _accountsRepository.createAccount(
      name: name,
      institution: institution,
      accountType: accountType,
      currency: currency,
      openingBalance: openingBalance,
      notes: 'Added during onboarding.',
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
    await _accountsRepository.updateAccount(
      id: id,
      name: name,
      institution: institution,
      accountType: accountType,
      currency: currency,
      openingBalance: openingBalance,
      notes: 'Updated during setup.',
    );
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
