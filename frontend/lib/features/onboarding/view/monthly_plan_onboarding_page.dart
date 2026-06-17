import 'dart:async';
import 'dart:convert';

import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:expense_tracker/features/accounts/models/financial_account.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/loans/models/loan.dart';
import 'package:expense_tracker/features/onboarding/repositories/onboarding_setup_writer.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/recurring/models/recurring_template.dart';
import 'package:expense_tracker/features/savings/models/savings_goal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _currencyOptions = <String>['NOK', 'INR', 'USD', 'EUR', 'GBP'];
const _accountTypeOptions = <String>[
  'checking',
  'savings',
  'investment',
  'fixed_deposit',
  'cash',
  'other',
];
const _accountTypeLabels = <String, String>{
  'checking': 'Current',
  'savings': 'Savings',
  'investment': 'Investment',
  'fixed_deposit': 'Fixed deposit',
  'cash': 'Cash',
  'other': 'Other',
};
const _setupDraftBoxName = 'monthly_setup_draft_v1';
const _accountDraftsKey = 'accountDrafts';
const _setupSteps = <_SetupStep>[
  _SetupStep.currency,
  _SetupStep.accounts,
  _SetupStep.salary,
  _SetupStep.housing,
  _SetupStep.loans,
  _SetupStep.groceries,
  _SetupStep.commitments,
  _SetupStep.transport,
  _SetupStep.savings,
  _SetupStep.review,
];

enum _SetupStep {
  currency,
  accounts,
  salary,
  housing,
  loans,
  groceries,
  commitments,
  transport,
  savings,
  review,
}

class MonthlyPlanOnboardingPage extends StatefulWidget {
  const MonthlyPlanOnboardingPage({
    this.setupWriter,
    this.completeOnFinish = true,
    super.key,
  });

  final OnboardingSetupWriter? setupWriter;
  final bool completeOnFinish;

  @override
  State<MonthlyPlanOnboardingPage> createState() =>
      _MonthlyPlanOnboardingPageState();
}

class _MonthlyPlanOnboardingPageState extends State<MonthlyPlanOnboardingPage> {
  late final OnboardingSetupWriter _setupWriter;
  late final bool _ownsSetupWriter;
  final _accounts = <_AccountDraftController>[];
  final _utilities = <_CommitmentDraftController>[];
  final _subscriptions = <_CommitmentDraftController>[];
  final _memberships = <_CommitmentDraftController>[];
  final _loans = <_LoanDraftController>[];
  final _groceryItems = <_NamedBudgetDraftController>[];
  final _transportItems = <_NamedBudgetDraftController>[];
  final _savingsGoals = <_SavingsDraftController>[];
  final _salaryAmountController = TextEditingController();
  final _salaryDayController = TextEditingController(text: '25');
  final _rentAmountController = TextEditingController();
  final _rentDayController = TextEditingController(text: '1');

  var _stepIndex = 0;
  var _currency = 'NOK';
  String? _salaryTemplateId;
  String? _housingTemplateId;
  var _accountsTouched = false;
  var _loadingExistingSetup = false;
  var _saving = false;
  String? _message;

  _SetupStep get _step => _setupSteps[_stepIndex];

  @override
  void initState() {
    super.initState();
    _setupWriter = widget.setupWriter ?? ApiOnboardingSetupWriter();
    _ownsSetupWriter = widget.setupWriter == null;
    _accounts.add(_AccountDraftController(currency: _currency));
    _resetCommitmentDrafts(_utilities);
    _resetCommitmentDrafts(_subscriptions);
    _resetCommitmentDrafts(_memberships);
    _loans.add(_LoanDraftController());
    _groceryItems.add(_NamedBudgetDraftController(name: 'Groceries'));
    _transportItems.add(_NamedBudgetDraftController(name: 'Transport'));
    _savingsGoals.add(_SavingsDraftController(targetCurrency: _currency));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadExistingSetup();
      }
    });
  }

  @override
  void dispose() {
    for (final account in _accounts) {
      account.dispose();
    }
    _salaryAmountController.dispose();
    _salaryDayController.dispose();
    _rentAmountController.dispose();
    _rentDayController.dispose();
    for (final loan in _loans) {
      loan.dispose();
    }
    for (final item in _groceryItems) {
      item.dispose();
    }
    for (final draft in _utilities) {
      draft.dispose();
    }
    for (final draft in _subscriptions) {
      draft.dispose();
    }
    for (final draft in _memberships) {
      draft.dispose();
    }
    for (final item in _transportItems) {
      item.dispose();
    }
    for (final goal in _savingsGoals) {
      goal.dispose();
    }
    if (_ownsSetupWriter) {
      _setupWriter.dispose();
    }
    super.dispose();
  }

  Future<void> _finish() {
    return _run(() async {
      final budgets = <String, double>{};
      final month = _monthKey(DateTime.now());

      for (final account in _accounts) {
        final name = account.nameController.text.trim();
        if (name.isEmpty) continue;
        if (account.existingId == null) {
          await _setupWriter.createFinancialAccount(
            name: name,
            institution: account.institutionController.text.trim(),
            accountType: account.accountType,
            currency: account.currency,
            openingBalance: _amountValue(account.balanceController),
          );
        } else {
          await _setupWriter.updateFinancialAccount(
            id: account.existingId!,
            name: name,
            institution: account.institutionController.text.trim(),
            accountType: account.accountType,
            currency: account.currency,
            openingBalance: _amountValue(account.balanceController),
          );
        }
      }

      final salaryAmount = _amountValue(_salaryAmountController);
      if (salaryAmount > 0) {
        await _saveRecurringTemplate(
          id: _salaryTemplateId,
          title: 'Salary',
          kind: 'income',
          amount: salaryAmount,
          category: 'Salary',
          currency: _currency,
          dayOfMonth: _dayValue(_salaryDayController, 'Salary day'),
        );
      }

      final rentAmount = _amountValue(_rentAmountController);
      if (rentAmount > 0) {
        budgets['Rent and housing'] = rentAmount;
        await _saveRecurringTemplate(
          id: _housingTemplateId,
          title: 'Rent and housing',
          kind: 'expense',
          amount: rentAmount,
          category: 'Rent and housing',
          currency: _currency,
          dayOfMonth: _dayValue(_rentDayController, 'Housing due day'),
        );
      }

      for (final loan in _loans) {
        final loanPrincipal = _amountValue(loan.principalController);
        final loanEmi = _amountValue(loan.emiController);
        if (!_loanHasContent(loan)) {
          continue;
        }
        if (loanPrincipal <= 0 || loanEmi <= 0) {
          throw const _OnboardingValidationException(
            'Each loan needs remaining principal and EMI, or remove that loan.',
          );
        }
        _addBudgetAmount(budgets, 'Loans / EMI', loanEmi);
        final name = loan.nameController.text.trim().isEmpty
            ? 'Loan'
            : loan.nameController.text.trim();
        final lender = loan.lenderController.text.trim();
        final principal = loanPrincipal;
        final interestRate = _amountValue(loan.interestController);
        final remainingEmis = _intValue(loan.monthsController);
        final dueDay = _dayValue(loan.dueDayController, 'Loan due day');
        if (loan.existingId == null) {
          await _setupWriter.createLoan(
            name: name,
            lender: lender,
            loanType: loan.loanType,
            principalAmount: principal,
            emiAmount: loanEmi,
            currency: _currency,
            interestRate: interestRate,
            rateType: loan.rateType,
            remainingEmis: remainingEmis,
            dueDay: dueDay,
          );
        } else {
          await _setupWriter.updateLoan(
            id: loan.existingId!,
            name: name,
            lender: lender,
            loanType: loan.loanType,
            principalAmount: principal,
            emiAmount: loanEmi,
            currency: _currency,
            interestRate: interestRate,
            rateType: loan.rateType,
            remainingEmis: remainingEmis,
            dueDay: dueDay,
          );
        }
      }

      _addNamedBudgets(
        budgets,
        baseCategory: 'Groceries',
        drafts: _groceryItems,
      );
      await _addCommitments(
        budgets,
        category: 'Utilities',
        drafts: _utilities,
        fallbackTitle: 'Utility bill',
      );
      await _addCommitments(
        budgets,
        category: 'Subscriptions',
        drafts: _subscriptions,
        fallbackTitle: 'Subscription',
      );
      await _addCommitments(
        budgets,
        category: 'Memberships',
        drafts: _memberships,
        fallbackTitle: 'Membership',
      );
      _addNamedBudgets(
        budgets,
        baseCategory: 'Transport',
        drafts: _transportItems,
      );

      for (final goal in _savingsGoals) {
        final savingsMonthly = _amountValue(goal.monthlyController);
        if (!_savingsHasContent(goal)) {
          continue;
        }
        if (savingsMonthly <= 0) {
          throw const _OnboardingValidationException(
            'Each savings goal needs a monthly amount, or remove that goal.',
          );
        }
        final savingsName = goal.nameController.text.trim();
        _addBudgetAmount(
          budgets,
          savingsName.isEmpty ? 'Savings' : 'Savings - $savingsName',
          savingsMonthly,
        );
        final explicitTarget = _amountValue(goal.targetController);
        final name = savingsName.isEmpty ? 'Savings' : savingsName;
        final targetAmount = explicitTarget > 0
            ? explicitTarget
            : savingsMonthly * 12;
        final familyVisibility = goal.showInFamily ? 'family' : 'private';
        if (goal.existingId == null) {
          await _setupWriter.createSavingsGoal(
            name: name,
            targetAmount: targetAmount,
            targetCurrency: goal.targetCurrency,
            sourceCurrency: _currency,
            monthlyTargetAmount: savingsMonthly,
            startMonth: month,
            accountName: goal.accountName,
            familyVisibility: familyVisibility,
          );
        } else {
          await _setupWriter.updateSavingsGoal(
            id: goal.existingId!,
            name: name,
            targetAmount: targetAmount,
            targetCurrency: goal.targetCurrency,
            sourceCurrency: _currency,
            monthlyTargetAmount: savingsMonthly,
            startMonth: month,
            accountName: goal.accountName,
            familyVisibility: familyVisibility,
          );
        }
      }

      if (budgets.isNotEmpty) {
        await _setupWriter.saveMonthlyPlan(
          month: month,
          currency: _currency,
          budgets: budgets,
        );
      }
      await _clearLocalAccountDraft();
      if (!mounted) return;
      if (widget.completeOnFinish) {
        await context.read<AuthCubit>().completeOnboarding();
      } else {
        Navigator.of(context).pop(true);
      }
    });
  }

  Future<void> _saveRecurringTemplate({
    required String? id,
    required String title,
    required String kind,
    required double amount,
    required String category,
    required String currency,
    required int dayOfMonth,
  }) {
    if (id == null) {
      return _setupWriter.createRecurringTemplate(
        title: title,
        kind: kind,
        amount: amount,
        category: category,
        currency: currency,
        dayOfMonth: dayOfMonth,
      );
    }
    return _setupWriter.updateRecurringTemplate(
      id: id,
      title: title,
      kind: kind,
      amount: amount,
      category: category,
      currency: currency,
      dayOfMonth: dayOfMonth,
    );
  }

  Future<void> _addCommitments(
    Map<String, double> budgets, {
    required String category,
    required List<_CommitmentDraftController> drafts,
    required String fallbackTitle,
  }) async {
    for (final draft in drafts) {
      final amount = _amountValue(draft.amountController);
      if (amount <= 0) {
        continue;
      }
      _addBudgetAmount(budgets, category, amount);
      final title = draft.nameController.text.trim().isEmpty
          ? fallbackTitle
          : draft.nameController.text.trim();
      await _saveRecurringTemplate(
        id: draft.existingId,
        title: title,
        kind: 'expense',
        amount: amount,
        category: category,
        currency: _currency,
        dayOfMonth: _dayValue(draft.dayController, '$title due day'),
      );
    }
  }

  void _addBudgetAmount(
    Map<String, double> budgets,
    String category,
    double amount,
  ) {
    if (amount <= 0) return;
    budgets[category] = (budgets[category] ?? 0) + amount;
  }

  void _addNamedBudgets(
    Map<String, double> budgets, {
    required String baseCategory,
    required List<_NamedBudgetDraftController> drafts,
  }) {
    for (final draft in drafts) {
      final amount = _amountValue(draft.amountController);
      if (amount <= 0) continue;
      final name = draft.nameController.text.trim();
      _addBudgetAmount(
        budgets,
        name.isEmpty || name.toLowerCase() == baseCategory.toLowerCase()
            ? baseCategory
            : '$baseCategory - $name',
        amount,
      );
    }
  }

  Future<void> _skipAll() {
    return _run(() async {
      if (widget.completeOnFinish) {
        await context.read<AuthCubit>().completeOnboarding();
      } else if (mounted) {
        Navigator.of(context).pop(false);
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await action();
    } on _OnboardingValidationException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Could not save setup. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _loadExistingSetup() async {
    if (_loadingExistingSetup) return;
    setState(() => _loadingExistingSetup = true);
    try {
      await _loadLocalAccountDraft();
      final month = _monthKey(DateTime.now());
      final accounts = await _withSetupFallback(
        _setupWriter.fetchFinancialAccounts(),
        const <FinancialAccount>[],
      );
      final plan = await _withSetupFallback(
        _setupWriter.fetchMonthlyPlan(month: month),
        MonthlyPlan(
          month: month,
          currency: _currency,
          totalBudget: 0,
          totalActual: 0,
          totalRemaining: 0,
          categories: const [],
        ),
      );
      final recurringTemplates = await _withSetupFallback(
        _setupWriter.fetchRecurringTemplates(),
        const <RecurringTemplate>[],
      );
      final loans = await _withSetupFallback(
        _setupWriter.fetchLoans(),
        const <Loan>[],
      );
      final savingsGoals = await _withSetupFallback(
        _setupWriter.fetchSavingsGoals(),
        const <SavingsGoal>[],
      );
      if (!mounted) return;
      setState(() {
        if (!_accountsTouched) {
          _applyExistingAccounts(accounts);
        }
        _applyExistingPlan(plan);
        _applyExistingRecurringTemplates(recurringTemplates);
        _applyExistingLoans(loans);
        _applyExistingSavingsGoals(savingsGoals);
        _loadingExistingSetup = false;
        _message = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingExistingSetup = false);
    }
  }

  Future<T> _withSetupFallback<T>(Future<T> future, T fallback) async {
    try {
      return await future;
    } catch (_) {
      return fallback;
    }
  }

  void _applyExistingAccounts(List<FinancialAccount> accounts) {
    if (accounts.isEmpty) {
      return;
    }
    for (final account in _accounts) {
      account.dispose();
    }
    _accounts
      ..clear()
      ..addAll(
        accounts.map((account) {
          final draft = _AccountDraftController(
            existingId: account.id,
            currency: account.currency,
          );
          draft.nameController.text = account.name;
          draft.institutionController.text = account.institution;
          draft.accountType = account.accountType;
          draft.balanceController.text = account.openingBalance.toStringAsFixed(
            2,
          );
          return draft;
        }),
      );
    if (_accounts.isNotEmpty) {
      _currency = _accounts.first.currency;
      for (final goal in _savingsGoals) {
        if (!goal.targetCurrencyTouched) {
          goal.targetCurrency = _currency;
        }
      }
    }
    _syncSavingsAccountSelection();
  }

  Future<void> _loadLocalAccountDraft() async {
    final box = await _openDraftBox();
    if (box == null || _accountsTouched) return;
    final raw = box.get(_accountDraftsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty || !mounted) return;
      setState(() => _applyAccountDraftPayload(decoded));
    } catch (_) {}
  }

  void _applyAccountDraftPayload(List<dynamic> items) {
    final drafts = <_AccountDraftController>[];
    for (final item in items) {
      if (item is! Map) continue;
      final currency = _normalizedCurrency(_stringValue(item['currency']));
      final draft = _AccountDraftController(
        existingId: _nullableStringValue(item['existingId']),
        currency: currency,
      );
      draft.nameController.text = _stringValue(item['name']);
      draft.institutionController.text = _stringValue(item['institution']);
      final accountType = _stringValue(item['accountType']);
      draft.accountType = _accountTypeOptions.contains(accountType)
          ? accountType
          : 'savings';
      draft.balanceController.text = _stringValue(item['balance']);
      if (_accountDraftHasContent(draft)) {
        drafts.add(draft);
      } else {
        draft.dispose();
      }
    }
    if (drafts.isEmpty) return;
    for (final account in _accounts) {
      account.dispose();
    }
    _accounts
      ..clear()
      ..addAll(drafts);
    _currency = _accounts.first.currency;
    for (final goal in _savingsGoals) {
      if (!goal.targetCurrencyTouched) {
        goal.targetCurrency = _currency;
      }
    }
    _syncSavingsAccountSelection();
  }

  void _markAccountsChanged() {
    _accountsTouched = true;
    _syncSavingsAccountSelection();
    unawaited(_saveLocalAccountDraft());
  }

  Future<void> _saveLocalAccountDraft() async {
    final box = await _openDraftBox();
    if (box == null) return;
    final payload = _accounts
        .where(_accountDraftHasContent)
        .map(
          (account) => <String, String?>{
            'existingId': account.existingId,
            'name': account.nameController.text,
            'institution': account.institutionController.text,
            'accountType': account.accountType,
            'currency': account.currency,
            'balance': account.balanceController.text,
          },
        )
        .toList(growable: false);
    if (payload.isEmpty) {
      await box.delete(_accountDraftsKey);
      return;
    }
    await box.put(_accountDraftsKey, jsonEncode(payload));
  }

  Future<void> _clearLocalAccountDraft() async {
    final box = await _openDraftBox();
    await box?.delete(_accountDraftsKey);
  }

  Future<Box<String>?> _openDraftBox() async {
    try {
      if (!Hive.isBoxOpen(_setupDraftBoxName)) {
        if (!kIsWeb) return null;
        await Hive.openBox<String>(_setupDraftBoxName);
      }
      return Hive.box<String>(_setupDraftBoxName);
    } catch (_) {
      return null;
    }
  }

  bool _accountDraftHasContent(_AccountDraftController account) {
    return account.existingId?.trim().isNotEmpty == true ||
        account.nameController.text.trim().isNotEmpty ||
        account.institutionController.text.trim().isNotEmpty ||
        account.balanceController.text.trim().isNotEmpty;
  }

  String _normalizedCurrency(String value) {
    final normalized = value.trim().toUpperCase();
    return _currencyOptions.contains(normalized) ? normalized : _currency;
  }

  String _stringValue(Object? value) {
    return value?.toString() ?? '';
  }

  String? _nullableStringValue(Object? value) {
    final text = _stringValue(value).trim();
    return text.isEmpty ? null : text;
  }

  void _applyExistingPlan(MonthlyPlan plan) {
    final currency = plan.currency.trim().toUpperCase();
    if (_currencyOptions.contains(currency)) {
      _currency = currency;
      for (final goal in _savingsGoals) {
        if (!goal.targetCurrencyTouched) {
          goal.targetCurrency = currency;
        }
      }
    }
    final budgets = plan.budgetsByCategory;
    _setAmountText(_rentAmountController, budgets['Rent and housing']);
    _applyNamedBudgetItems(
      budgets,
      baseCategory: 'Groceries',
      drafts: _groceryItems,
    );
    _applyNamedBudgetItems(
      budgets,
      baseCategory: 'Transport',
      drafts: _transportItems,
    );
    _applySavingsBudgetFallback(budgets);
  }

  void _applyExistingRecurringTemplates(List<RecurringTemplate> templates) {
    final activeMonthly = templates
        .where(
          (template) =>
              template.active && template.frequency.toLowerCase() == 'monthly',
        )
        .toList(growable: false);
    final salary = _firstTemplate(
      activeMonthly,
      kind: 'income',
      category: 'Salary',
    );
    if (salary != null) {
      _salaryTemplateId = salary.id;
      _salaryAmountController.text = _formatAmount(salary.amount);
      _salaryDayController.text = salary.dayOfMonth.toString();
      _applyCurrencyIfKnown(salary.currency);
    }

    final housing = _firstTemplate(
      activeMonthly,
      kind: 'expense',
      category: 'Rent and housing',
    );
    if (housing != null) {
      _housingTemplateId = housing.id;
      _rentAmountController.text = _formatAmount(housing.amount);
      _rentDayController.text = housing.dayOfMonth.toString();
      _applyCurrencyIfKnown(housing.currency);
    }

    _applyCommitmentTemplates(
      activeMonthly,
      category: 'Utilities',
      drafts: _utilities,
    );
    _applyCommitmentTemplates(
      activeMonthly,
      category: 'Subscriptions',
      drafts: _subscriptions,
    );
    _applyCommitmentTemplates(
      activeMonthly,
      category: 'Memberships',
      drafts: _memberships,
    );
  }

  RecurringTemplate? _firstTemplate(
    List<RecurringTemplate> templates, {
    required String kind,
    required String category,
  }) {
    for (final template in templates) {
      if (template.kind.toLowerCase() == kind &&
          template.category.toLowerCase() == category.toLowerCase()) {
        return template;
      }
    }
    return null;
  }

  void _applyCommitmentTemplates(
    List<RecurringTemplate> templates, {
    required String category,
    required List<_CommitmentDraftController> drafts,
  }) {
    final matches = templates
        .where(
          (template) =>
              template.kind.toLowerCase() == 'expense' &&
              template.category.toLowerCase() == category.toLowerCase(),
        )
        .toList(growable: false);
    if (matches.isEmpty) return;
    for (final draft in drafts) {
      draft.dispose();
    }
    drafts
      ..clear()
      ..addAll(
        matches.map((template) {
          final draft = _CommitmentDraftController(existingId: template.id);
          draft.nameController.text = template.title;
          draft.amountController.text = _formatAmount(template.amount);
          draft.dayController.text = template.dayOfMonth.toString();
          _applyCurrencyIfKnown(template.currency);
          return draft;
        }),
      );
  }

  void _applyExistingLoans(List<Loan> loans) {
    final activeLoans = loans.where((loan) => !loan.archived).toList();
    if (activeLoans.isEmpty) return;
    for (final loan in _loans) {
      loan.dispose();
    }
    _loans
      ..clear()
      ..addAll(
        activeLoans.map((loan) {
          final draft = _LoanDraftController(existingId: loan.id);
          draft.nameController.text = loan.name;
          draft.lenderController.text = loan.lender;
          draft.loanType = _normalizeLoanType(loan.loanType);
          draft.principalController.text = _formatAmount(
            loan.estimatedOutstanding > 0
                ? loan.estimatedOutstanding
                : loan.principalAmount,
          );
          draft.emiController.text = _formatAmount(loan.emiAmount);
          draft.interestController.text = _formatAmount(loan.interestRate);
          draft.rateType = _normalizeLoanRateType(loan.rateType);
          final monthsLeft = loan.remainingEmis ?? loan.totalEmis;
          if (monthsLeft > 0) {
            draft.monthsController.text = monthsLeft.toString();
          }
          draft.dueDayController.text = loan.dueDay.toString();
          _applyCurrencyIfKnown(loan.currency);
          return draft;
        }),
      );
  }

  void _applyExistingSavingsGoals(List<SavingsGoal> goals) {
    final activeGoals = goals.where((goal) => !goal.archived).toList();
    if (activeGoals.isEmpty) return;
    for (final goal in _savingsGoals) {
      goal.dispose();
    }
    _savingsGoals
      ..clear()
      ..addAll(
        activeGoals.map((goal) {
          _applyCurrencyIfKnown(goal.sourceCurrency);
          final draft = _SavingsDraftController(
            existingId: goal.id,
            targetCurrency: _normalizedCurrency(goal.targetCurrency),
          );
          draft.nameController.text = goal.name;
          draft.monthlyController.text = _formatAmount(
            goal.monthlyTargetAmount,
          );
          draft.targetController.text = _formatAmount(goal.targetAmount);
          draft.accountName = _accountLabelForStoredName(goal.accountName);
          draft.showInFamily = goal.familyVisibility == 'family';
          return draft;
        }),
      );
    _syncSavingsAccountSelection();
  }

  void _applyNamedBudgetItems(
    Map<String, double> budgets, {
    required String baseCategory,
    required List<_NamedBudgetDraftController> drafts,
  }) {
    final matches = <_NamedBudgetDraftController>[];
    for (final entry in budgets.entries) {
      if (entry.value <= 0) continue;
      final category = entry.key.trim();
      if (category == baseCategory) {
        matches.add(
          _NamedBudgetDraftController(
            name: baseCategory,
            amount: _formatAmount(entry.value),
          ),
        );
      } else if (category.toLowerCase().startsWith(
        '${baseCategory.toLowerCase()} - ',
      )) {
        matches.add(
          _NamedBudgetDraftController(
            name: category.substring(baseCategory.length + 3),
            amount: _formatAmount(entry.value),
          ),
        );
      }
    }
    if (matches.isEmpty) return;
    for (final draft in drafts) {
      draft.dispose();
    }
    drafts
      ..clear()
      ..addAll(matches);
  }

  void _applySavingsBudgetFallback(Map<String, double> budgets) {
    if (_savingsGoals.any(_savingsHasContent)) return;
    final savings = budgets['Savings'];
    if (savings == null || savings <= 0) return;
    _savingsGoals.first.monthlyController.text = _formatAmount(savings);
  }

  void _applyCurrencyIfKnown(String value) {
    final currency = value.trim().toUpperCase();
    if (!_currencyOptions.contains(currency)) return;
    _currency = currency;
    for (final goal in _savingsGoals) {
      if (!goal.targetCurrencyTouched) {
        goal.targetCurrency = currency;
      }
    }
  }

  void _setAmountText(TextEditingController controller, double? value) {
    if (value == null || value <= 0 || controller.text.trim().isNotEmpty) {
      return;
    }
    controller.text = _formatAmount(value);
  }

  String _formatAmount(double value) {
    final decimals = value.truncateToDouble() == value ? 0 : 2;
    return value.toStringAsFixed(decimals);
  }

  String _normalizeLoanType(String value) {
    const options = [
      'Car',
      'Home',
      'Personal',
      'Consumer loan',
      'Education',
      'Other',
    ];
    for (final option in options) {
      if (option.toLowerCase() == value.toLowerCase()) {
        return option;
      }
    }
    return 'Other';
  }

  String _normalizeLoanRateType(String value) {
    const options = ['floating', 'fixed', 'unknown'];
    final normalized = value.toLowerCase();
    return options.contains(normalized) ? normalized : 'unknown';
  }

  void _nextStep() {
    if (_stepIndex >= _setupSteps.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _stepIndex += 1;
      _message = null;
      _syncSavingsAccountSelection();
    });
  }

  void _previousStep() {
    if (_stepIndex == 0) return;
    setState(() {
      _stepIndex -= 1;
      _message = null;
    });
  }

  void _skipStep() {
    _clearStep(_step);
    _nextStep();
  }

  void _clearStep(_SetupStep step) {
    switch (step) {
      case _SetupStep.currency:
        break;
      case _SetupStep.accounts:
        for (final account in _accounts) {
          account.dispose();
        }
        _accounts
          ..clear()
          ..add(_AccountDraftController(currency: _currency));
        for (final goal in _savingsGoals) {
          goal.accountName = '';
        }
        _accountsTouched = true;
        unawaited(_clearLocalAccountDraft());
        break;
      case _SetupStep.salary:
        _salaryAmountController.clear();
        break;
      case _SetupStep.housing:
        _rentAmountController.clear();
        break;
      case _SetupStep.loans:
        _resetLoanDrafts();
        break;
      case _SetupStep.groceries:
        _resetNamedBudgetDrafts(_groceryItems, name: 'Groceries');
        break;
      case _SetupStep.commitments:
        _resetCommitmentDrafts(_utilities);
        _resetCommitmentDrafts(_subscriptions);
        _resetCommitmentDrafts(_memberships);
        break;
      case _SetupStep.transport:
        _resetNamedBudgetDrafts(_transportItems, name: 'Transport');
        break;
      case _SetupStep.savings:
        _resetSavingsDrafts();
        break;
      case _SetupStep.review:
        break;
    }
  }

  void _syncSavingsAccountSelection() {
    final accountNames = _accountNames;
    for (final goal in _savingsGoals) {
      if (accountNames.isEmpty) {
        goal.accountName = '';
      } else if (!accountNames.contains(goal.accountName)) {
        goal.accountName = accountNames.first;
      }
    }
  }

  List<String> get _accountNames {
    return _accounts
        .map(_accountLabel)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String _accountLabel(_AccountDraftController account) {
    final name = account.nameController.text.trim();
    final institution = account.institutionController.text.trim();
    if (name.isEmpty) return '';
    if (institution.isEmpty) return name;
    return '$name - $institution';
  }

  String _accountLabelForStoredName(String storedName) {
    final raw = storedName.trim();
    if (raw.isEmpty) return raw;
    final labels = _accountNames;
    if (labels.contains(raw)) return raw;
    for (final account in _accounts) {
      if (account.nameController.text.trim() == raw) {
        return _accountLabel(account);
      }
    }
    return raw;
  }

  double _amountValue(TextEditingController controller) {
    return _parseAmount(controller.text) ?? 0;
  }

  int _intValue(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  int _dayValue(TextEditingController controller, String field) {
    final value = int.tryParse(controller.text.trim()) ?? 0;
    if (value < 1 || value > 31) {
      throw _OnboardingValidationException('$field must be between 1 and 31.');
    }
    return value;
  }

  String _monthKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
  }

  void _resetCommitmentDrafts(List<_CommitmentDraftController> drafts) {
    for (final draft in drafts) {
      draft.dispose();
    }
    drafts
      ..clear()
      ..add(_CommitmentDraftController());
  }

  void _resetLoanDrafts() {
    for (final loan in _loans) {
      loan.dispose();
    }
    _loans
      ..clear()
      ..add(_LoanDraftController());
  }

  void _resetNamedBudgetDrafts(
    List<_NamedBudgetDraftController> drafts, {
    required String name,
  }) {
    for (final draft in drafts) {
      draft.dispose();
    }
    drafts
      ..clear()
      ..add(_NamedBudgetDraftController(name: name));
  }

  void _resetSavingsDrafts() {
    for (final goal in _savingsGoals) {
      goal.dispose();
    }
    _savingsGoals
      ..clear()
      ..add(_SavingsDraftController(targetCurrency: _currency));
    _syncSavingsAccountSelection();
  }

  void _addLoanDraft() {
    setState(() => _loans.add(_LoanDraftController()));
  }

  void _removeLoanDraft(int index) {
    setState(() {
      _loans.removeAt(index).dispose();
      if (_loans.isEmpty) {
        _loans.add(_LoanDraftController());
      }
    });
  }

  void _addNamedBudgetDraft(
    List<_NamedBudgetDraftController> drafts, {
    required String name,
  }) {
    setState(() => drafts.add(_NamedBudgetDraftController(name: name)));
  }

  void _removeNamedBudgetDraft(
    List<_NamedBudgetDraftController> drafts,
    int index, {
    required String name,
  }) {
    setState(() {
      drafts.removeAt(index).dispose();
      if (drafts.isEmpty) {
        drafts.add(_NamedBudgetDraftController(name: name));
      }
    });
  }

  void _addSavingsDraft() {
    setState(() {
      _savingsGoals.add(_SavingsDraftController(targetCurrency: _currency));
      _syncSavingsAccountSelection();
    });
  }

  void _removeSavingsDraft(int index) {
    setState(() {
      _savingsGoals.removeAt(index).dispose();
      if (_savingsGoals.isEmpty) {
        _savingsGoals.add(_SavingsDraftController(targetCurrency: _currency));
      }
      _syncSavingsAccountSelection();
    });
  }

  void _addCommitmentDraft(List<_CommitmentDraftController> drafts) {
    setState(() => drafts.add(_CommitmentDraftController()));
  }

  void _removeCommitmentDraft(
    List<_CommitmentDraftController> drafts,
    int index,
  ) {
    setState(() {
      drafts.removeAt(index).dispose();
      if (drafts.isEmpty) {
        drafts.add(_CommitmentDraftController());
      }
    });
  }

  double _commitmentTotal(List<_CommitmentDraftController> drafts) {
    return drafts.fold<double>(
      0,
      (sum, draft) => sum + _amountValue(draft.amountController),
    );
  }

  int _filledCommitmentCount(List<_CommitmentDraftController> drafts) {
    return drafts
        .where((draft) => _amountValue(draft.amountController) > 0)
        .length;
  }

  bool _loanHasContent(_LoanDraftController loan) {
    return loan.existingId?.trim().isNotEmpty == true ||
        loan.nameController.text.trim().isNotEmpty ||
        loan.lenderController.text.trim().isNotEmpty ||
        loan.principalController.text.trim().isNotEmpty ||
        loan.emiController.text.trim().isNotEmpty ||
        loan.interestController.text.trim().isNotEmpty ||
        loan.monthsController.text.trim().isNotEmpty;
  }

  bool _savingsHasContent(_SavingsDraftController goal) {
    return goal.existingId?.trim().isNotEmpty == true ||
        goal.nameController.text.trim().isNotEmpty ||
        goal.monthlyController.text.trim().isNotEmpty ||
        goal.targetController.text.trim().isNotEmpty;
  }

  double _namedBudgetTotal(List<_NamedBudgetDraftController> drafts) {
    return drafts.fold<double>(
      0,
      (sum, draft) => sum + _amountValue(draft.amountController),
    );
  }

  int _filledNamedBudgetCount(List<_NamedBudgetDraftController> drafts) {
    return drafts
        .where((draft) => _amountValue(draft.amountController) > 0)
        .length;
  }

  String get _stepTitle {
    return switch (_step) {
      _SetupStep.currency => 'Currency',
      _SetupStep.accounts => 'Bank accounts',
      _SetupStep.salary => 'Salary',
      _SetupStep.housing => 'Rent and housing',
      _SetupStep.loans => 'Loans',
      _SetupStep.groceries => 'Groceries',
      _SetupStep.commitments => 'Bills and subscriptions',
      _SetupStep.transport => 'Transport',
      _SetupStep.savings => 'Savings',
      _SetupStep.review => 'Review',
    };
  }

  String get _stepDescription {
    return switch (_step) {
      _SetupStep.currency =>
        'Choose the main currency for your monthly plan. You can still log expenses in other currencies later.',
      _SetupStep.accounts =>
        'Add the accounts you already use. Skip anything you do not want to enter right now.',
      _SetupStep.salary =>
        'Optional. Add your usual payday and monthly income so the month starts from real cash flow.',
      _SetupStep.housing =>
        'Add rent, mortgage, or any regular housing payment for this month.',
      _SetupStep.loans =>
        'Use the remaining principal, EMI, and current rate from your lender. You can edit the details later.',
      _SetupStep.groceries => 'Set a simple grocery budget for the month.',
      _SetupStep.commitments =>
        'Add each utility, subscription, and membership separately so you can track them one by one.',
      _SetupStep.transport =>
        'Set a transport budget for fuel, tickets, tolls, or parking.',
      _SetupStep.savings =>
        'Add a savings goal now, or skip and set it up once you are inside the app.',
      _SetupStep.review =>
        'Check the basics, then finish setup. You can return and change any of this later.',
    };
  }

  IconData get _stepIcon {
    return switch (_step) {
      _SetupStep.currency => Icons.payments_outlined,
      _SetupStep.accounts => Icons.account_balance_outlined,
      _SetupStep.salary => Icons.work_outline,
      _SetupStep.housing => Icons.home_outlined,
      _SetupStep.loans => Icons.request_quote_outlined,
      _SetupStep.groceries => Icons.shopping_basket_outlined,
      _SetupStep.commitments => Icons.receipt_long_outlined,
      _SetupStep.transport => Icons.directions_car_outlined,
      _SetupStep.savings => Icons.savings_outlined,
      _SetupStep.review => Icons.fact_check_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_stepIndex + 1) / _setupSteps.length;
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: _saving || _stepIndex == 0
                            ? null
                            : _previousStep,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: Text(
                          '${_stepIndex + 1} of ${_setupSteps.length}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Set up later',
                        onPressed: _saving ? null : _skipAll,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Icon(_stepIcon, size: 42, color: theme.colorScheme.primary),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _stepTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _stepDescription,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: KeyedSubtree(
                              key: ValueKey(_step),
                              child: _buildStep(),
                            ),
                          ),
                          if (_message != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              _message!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ),
                    ),
                  ),
                  if (_step == _SetupStep.review)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('onboarding-complete-setup'),
                        onPressed: _saving ? null : _finish,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: const Text('Complete setup'),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const ValueKey('onboarding-complete-setup'),
                            onPressed: _saving ? null : _finish,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Complete setup'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _nextStep,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_forward),
                            label: Text(
                              _stepIndex == _setupSteps.length - 2
                                  ? 'Review'
                                  : 'Next',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextButton.icon(
                      onPressed: _saving ? null : _skipStep,
                      icon: const Icon(Icons.skip_next_outlined),
                      label: const Text('Skip this step'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    return switch (_step) {
      _SetupStep.currency => _currencyStep(),
      _SetupStep.accounts => _accountsStep(),
      _SetupStep.salary => _salaryStep(),
      _SetupStep.housing => _housingStep(),
      _SetupStep.loans => _loansStep(),
      _SetupStep.groceries => _groceriesStep(),
      _SetupStep.commitments => _commitmentsStep(),
      _SetupStep.transport => _transportStep(),
      _SetupStep.savings => _savingsStep(),
      _SetupStep.review => _reviewStep(),
    };
  }

  Widget _currencyStep() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _currency,
          decoration: const InputDecoration(
            labelText: 'Primary currency',
            border: OutlineInputBorder(),
          ),
          items: _currencyOptions
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(growable: false),
          onChanged: _saving
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    final previousCurrency = _currency;
                    _currency = value;
                    for (final goal in _savingsGoals) {
                      if (!goal.targetCurrencyTouched ||
                          goal.targetCurrency == previousCurrency) {
                        goal.targetCurrency = value;
                      }
                    }
                    for (final account in _accounts) {
                      if (account.currency.isEmpty) {
                        account.currency = value;
                      }
                    }
                  });
                },
        ),
      ],
    );
  }

  Widget _accountsStep() {
    return Column(
      children: [
        for (var index = 0; index < _accounts.length; index++) ...[
          _AccountEditor(
            controller: _accounts[index],
            enabled: !_saving,
            onChanged: () => setState(_markAccountsChanged),
            onRemove: _accounts.length == 1
                ? null
                : () {
                    setState(() {
                      _accounts.removeAt(index).dispose();
                      _markAccountsChanged();
                    });
                  },
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _saving
                ? null
                : () {
                    setState(() {
                      _accounts.add(
                        _AccountDraftController(currency: _currency),
                      );
                      _markAccountsChanged();
                    });
                  },
            icon: const Icon(Icons.add),
            label: const Text('Add account'),
          ),
        ),
      ],
    );
  }

  Widget _salaryStep() {
    return Column(
      children: [
        _MoneyField(
          controller: _salaryAmountController,
          currency: _currency,
          label: 'Monthly salary',
          enabled: !_saving,
        ),
        const SizedBox(height: AppSpacing.md),
        _DayField(
          controller: _salaryDayController,
          label: 'Salary day',
          enabled: !_saving,
        ),
      ],
    );
  }

  Widget _housingStep() {
    return Column(
      children: [
        _MoneyField(
          controller: _rentAmountController,
          currency: _currency,
          label: 'Rent or housing payment',
          enabled: !_saving,
        ),
        const SizedBox(height: AppSpacing.md),
        _DayField(
          controller: _rentDayController,
          label: 'Payment day',
          enabled: !_saving,
        ),
      ],
    );
  }

  Widget _loansStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < _loans.length; index++) ...[
          _LoanDraftEditor(
            controller: _loans[index],
            currency: _currency,
            enabled: !_saving,
            canRemove: _loans.length > 1,
            fieldKeyPrefix: 'loan-$index',
            onChanged: () => setState(() {}),
            onRemove: () => _removeLoanDraft(index),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        OutlinedButton.icon(
          key: const ValueKey('loans-add'),
          onPressed: _saving ? null : _addLoanDraft,
          icon: const Icon(Icons.add),
          label: const Text('Add another loan'),
        ),
      ],
    );
  }

  Widget _groceriesStep() {
    return _NamedBudgetSection(
      title: 'Grocery items',
      description: 'Break the grocery plan into useful buckets.',
      icon: Icons.shopping_basket_outlined,
      itemLabel: 'Grocery item',
      itemHint: 'Vegetables',
      addLabel: 'Add grocery item',
      currency: _currency,
      drafts: _groceryItems,
      enabled: !_saving,
      sectionKeyPrefix: 'groceries',
      onAdd: () => _addNamedBudgetDraft(_groceryItems, name: 'Groceries'),
      onRemove: (index) =>
          _removeNamedBudgetDraft(_groceryItems, index, name: 'Groceries'),
    );
  }

  Widget _transportStep() {
    return _NamedBudgetSection(
      title: 'Transport costs',
      description: 'Add fuel, tickets, tolls, parking, or other travel costs.',
      icon: Icons.directions_car_outlined,
      itemLabel: 'Transport item',
      itemHint: 'Bus tickets',
      addLabel: 'Add transport item',
      currency: _currency,
      drafts: _transportItems,
      enabled: !_saving,
      sectionKeyPrefix: 'transport',
      onAdd: () => _addNamedBudgetDraft(_transportItems, name: 'Transport'),
      onRemove: (index) =>
          _removeNamedBudgetDraft(_transportItems, index, name: 'Transport'),
    );
  }

  Widget _savingsStep() {
    final accountNames = _accountNames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < _savingsGoals.length; index++) ...[
          _SavingsDraftEditor(
            controller: _savingsGoals[index],
            currency: _currency,
            accountNames: accountNames,
            enabled: !_saving,
            canRemove: _savingsGoals.length > 1,
            fieldKeyPrefix: 'savings-$index',
            onChanged: () => setState(() {}),
            onRemove: () => _removeSavingsDraft(index),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        OutlinedButton.icon(
          key: const ValueKey('savings-add'),
          onPressed: _saving ? null : _addSavingsDraft,
          icon: const Icon(Icons.add),
          label: const Text('Add savings goal'),
        ),
      ],
    );
  }

  Widget _commitmentsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CommitmentSection(
          title: 'Utilities',
          description:
              'Add electricity, internet, mobile, and other fixed bills.',
          icon: Icons.flash_on_outlined,
          itemLabel: 'Bill name',
          itemHint: 'Electricity',
          addLabel: 'Add utility',
          currency: _currency,
          drafts: _utilities,
          enabled: !_saving,
          sectionKeyPrefix: 'utilities',
          onAdd: () => _addCommitmentDraft(_utilities),
          onRemove: (index) => _removeCommitmentDraft(_utilities, index),
        ),
        const SizedBox(height: AppSpacing.md),
        _CommitmentSection(
          title: 'Subscriptions',
          description:
              'Track streaming, software, and other monthly services one by one.',
          icon: Icons.subscriptions_outlined,
          itemLabel: 'Subscription name',
          itemHint: 'Netflix',
          addLabel: 'Add subscription',
          currency: _currency,
          drafts: _subscriptions,
          enabled: !_saving,
          sectionKeyPrefix: 'subscriptions',
          onAdd: () => _addCommitmentDraft(_subscriptions),
          onRemove: (index) => _removeCommitmentDraft(_subscriptions, index),
        ),
        const SizedBox(height: AppSpacing.md),
        _CommitmentSection(
          title: 'Memberships',
          description:
              'Add gym, clubs, childcare, or any recurring membership fees.',
          icon: Icons.card_membership_outlined,
          itemLabel: 'Membership name',
          itemHint: 'Gym',
          addLabel: 'Add membership',
          currency: _currency,
          drafts: _memberships,
          enabled: !_saving,
          sectionKeyPrefix: 'memberships',
          onAdd: () => _addCommitmentDraft(_memberships),
          onRemove: (index) => _removeCommitmentDraft(_memberships, index),
        ),
      ],
    );
  }

  Widget _reviewStep() {
    final rows = _reviewRows();
    if (rows.isEmpty) {
      return const _ReviewEmpty();
    }
    return Column(
      children: [
        for (final row in rows) ...[
          _ReviewRow(icon: row.icon, label: row.label, value: row.value),
          const Divider(height: AppSpacing.lg),
        ],
      ],
    );
  }

  List<_ReviewItem> _reviewRows() {
    final rows = <_ReviewItem>[
      _ReviewItem(Icons.payments_outlined, 'Currency', _currency),
    ];
    final accounts = _accountNames;
    if (accounts.isNotEmpty) {
      rows.add(
        _ReviewItem(
          Icons.account_balance_outlined,
          'Accounts',
          accounts.join(', '),
        ),
      );
    }
    final salary = _amountValue(_salaryAmountController);
    if (salary > 0) {
      rows.add(
        _ReviewItem(
          Icons.work_outline,
          'Salary',
          '$_currency ${salary.toStringAsFixed(0)}',
        ),
      );
    }
    final rent = _amountValue(_rentAmountController);
    if (rent > 0) {
      rows.add(
        _ReviewItem(
          Icons.home_outlined,
          'Housing',
          '$_currency ${rent.toStringAsFixed(0)}',
        ),
      );
    }
    final loanEmi = _loans.fold<double>(
      0,
      (sum, loan) => sum + _amountValue(loan.emiController),
    );
    if (loanEmi > 0) {
      final count = _loans.where(_loanHasContent).length;
      rows.add(
        _ReviewItem(
          Icons.request_quote_outlined,
          count > 1 ? 'Loan EMI ($count)' : 'Loan EMI',
          '$_currency ${loanEmi.toStringAsFixed(0)}',
        ),
      );
    }
    final groceries = _namedBudgetTotal(_groceryItems);
    if (groceries > 0) {
      final count = _filledNamedBudgetCount(_groceryItems);
      rows.add(
        _ReviewItem(
          Icons.shopping_basket_outlined,
          count > 1 ? 'Groceries ($count)' : 'Groceries',
          '$_currency ${groceries.toStringAsFixed(0)}',
        ),
      );
    }
    for (final item in [
      (Icons.receipt_long_outlined, 'Utilities', _utilities),
      (Icons.subscriptions_outlined, 'Subscriptions', _subscriptions),
      (Icons.card_membership_outlined, 'Memberships', _memberships),
    ]) {
      final total = _commitmentTotal(item.$3);
      if (total <= 0) {
        continue;
      }
      final count = _filledCommitmentCount(item.$3);
      final label = count > 1 ? '${item.$2} ($count)' : item.$2;
      rows.add(
        _ReviewItem(item.$1, label, '$_currency ${total.toStringAsFixed(0)}'),
      );
    }
    final transport = _namedBudgetTotal(_transportItems);
    if (transport > 0) {
      final count = _filledNamedBudgetCount(_transportItems);
      rows.add(
        _ReviewItem(
          Icons.directions_car_outlined,
          count > 1 ? 'Transport ($count)' : 'Transport',
          '$_currency ${transport.toStringAsFixed(0)}',
        ),
      );
    }
    final savings = _savingsGoals.fold<double>(
      0,
      (sum, goal) => sum + _amountValue(goal.monthlyController),
    );
    if (savings > 0) {
      final count = _savingsGoals.where(_savingsHasContent).length;
      rows.add(
        _ReviewItem(
          Icons.savings_outlined,
          count > 1 ? 'Savings ($count)' : 'Savings',
          '$_currency ${savings.toStringAsFixed(0)}',
        ),
      );
    }
    return rows;
  }
}

class _LoanDraftController {
  _LoanDraftController({this.existingId})
    : nameController = TextEditingController(),
      lenderController = TextEditingController(),
      principalController = TextEditingController(),
      emiController = TextEditingController(),
      interestController = TextEditingController(),
      monthsController = TextEditingController(),
      dueDayController = TextEditingController(text: '18');

  final String? existingId;
  final TextEditingController nameController;
  final TextEditingController lenderController;
  final TextEditingController principalController;
  final TextEditingController emiController;
  final TextEditingController interestController;
  final TextEditingController monthsController;
  final TextEditingController dueDayController;
  String loanType = 'Car';
  String rateType = 'floating';

  void dispose() {
    nameController.dispose();
    lenderController.dispose();
    principalController.dispose();
    emiController.dispose();
    interestController.dispose();
    monthsController.dispose();
    dueDayController.dispose();
  }
}

class _NamedBudgetDraftController {
  _NamedBudgetDraftController({required String name, String amount = ''})
    : nameController = TextEditingController(text: name),
      amountController = TextEditingController(text: amount);

  final TextEditingController nameController;
  final TextEditingController amountController;

  void dispose() {
    nameController.dispose();
    amountController.dispose();
  }
}

class _SavingsDraftController {
  _SavingsDraftController({this.existingId, required this.targetCurrency})
    : nameController = TextEditingController(),
      monthlyController = TextEditingController(),
      targetController = TextEditingController();

  final String? existingId;
  final TextEditingController nameController;
  final TextEditingController monthlyController;
  final TextEditingController targetController;
  String targetCurrency;
  String accountName = '';
  bool showInFamily = false;
  bool targetCurrencyTouched = false;

  void dispose() {
    nameController.dispose();
    monthlyController.dispose();
    targetController.dispose();
  }
}

class _LoanDraftEditor extends StatelessWidget {
  const _LoanDraftEditor({
    required this.controller,
    required this.currency,
    required this.enabled,
    required this.canRemove,
    required this.fieldKeyPrefix,
    required this.onChanged,
    required this.onRemove,
  });

  final _LoanDraftController controller;
  final String currency;
  final bool enabled;
  final bool canRemove;
  final String fieldKeyPrefix;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('$fieldKeyPrefix-name'),
                    controller: controller.nameController,
                    enabled: enabled,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Loan name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: 'Remove loan',
                  onPressed: enabled && canRemove ? onRemove : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: ValueKey('$fieldKeyPrefix-lender'),
              controller: controller.lenderController,
              enabled: enabled,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Lender',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: controller.loanType,
              decoration: const InputDecoration(
                labelText: 'Loan type',
                border: OutlineInputBorder(),
              ),
              items:
                  const [
                        'Car',
                        'Home',
                        'Personal',
                        'Consumer loan',
                        'Education',
                        'Other',
                      ]
                      .map(
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(growable: false),
              onChanged: enabled
                  ? (value) {
                      if (value == null) return;
                      controller.loanType = value;
                      onChanged();
                    }
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            _MoneyField(
              fieldKey: ValueKey('$fieldKeyPrefix-principal'),
              controller: controller.principalController,
              currency: currency,
              label: 'Remaining principal',
              enabled: enabled,
            ),
            const SizedBox(height: AppSpacing.sm),
            _MoneyField(
              fieldKey: ValueKey('$fieldKeyPrefix-emi'),
              controller: controller.emiController,
              currency: currency,
              label: 'Monthly EMI',
              enabled: enabled,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('$fieldKeyPrefix-interest'),
                    controller: controller.interestController,
                    enabled: enabled,
                    onChanged: (_) => onChanged(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Interest rate',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: controller.rateType,
                    decoration: const InputDecoration(
                      labelText: 'Rate',
                      border: OutlineInputBorder(),
                    ),
                    items: const ['floating', 'fixed', 'unknown']
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(_titleCase(item)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: enabled
                        ? (value) {
                            if (value == null) return;
                            controller.rateType = value;
                            onChanged();
                          }
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('$fieldKeyPrefix-months'),
                    controller: controller.monthsController,
                    enabled: enabled,
                    onChanged: (_) => onChanged(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Months left',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _DayField(
                    fieldKey: ValueKey('$fieldKeyPrefix-day'),
                    controller: controller.dueDayController,
                    label: 'EMI day',
                    enabled: enabled,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NamedBudgetSection extends StatelessWidget {
  const _NamedBudgetSection({
    required this.title,
    required this.description,
    required this.icon,
    required this.itemLabel,
    required this.itemHint,
    required this.addLabel,
    required this.currency,
    required this.drafts,
    required this.enabled,
    required this.sectionKeyPrefix,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final String description;
  final IconData icon;
  final String itemLabel;
  final String itemHint;
  final String addLabel;
  final String currency;
  final List<_NamedBudgetDraftController> drafts;
  final bool enabled;
  final String sectionKeyPrefix;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            TextButton.icon(
              key: ValueKey('$sectionKeyPrefix-add'),
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.add),
              label: Text(addLabel),
            ),
          ],
        ),
        Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var index = 0; index < drafts.length; index++) ...[
          _NamedBudgetDraftEditor(
            controller: drafts[index],
            currency: currency,
            itemLabel: itemLabel,
            itemHint: itemHint,
            enabled: enabled,
            canRemove: drafts.length > 1,
            fieldKeyPrefix: '$sectionKeyPrefix-$index',
            onRemove: () => onRemove(index),
          ),
          if (index < drafts.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _NamedBudgetDraftEditor extends StatelessWidget {
  const _NamedBudgetDraftEditor({
    required this.controller,
    required this.currency,
    required this.itemLabel,
    required this.itemHint,
    required this.enabled,
    required this.canRemove,
    required this.fieldKeyPrefix,
    required this.onRemove,
  });

  final _NamedBudgetDraftController controller;
  final String currency;
  final String itemLabel;
  final String itemHint;
  final bool enabled;
  final bool canRemove;
  final String fieldKeyPrefix;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                key: ValueKey('$fieldKeyPrefix-name'),
                controller: controller.nameController,
                enabled: enabled,
                decoration: InputDecoration(
                  labelText: itemLabel,
                  hintText: itemHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 2,
              child: _MoneyField(
                fieldKey: ValueKey('$fieldKeyPrefix-amount'),
                controller: controller.amountController,
                currency: currency,
                label: 'Amount',
                enabled: enabled,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              tooltip: 'Remove item',
              onPressed: enabled && canRemove ? onRemove : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavingsDraftEditor extends StatelessWidget {
  const _SavingsDraftEditor({
    required this.controller,
    required this.currency,
    required this.accountNames,
    required this.enabled,
    required this.canRemove,
    required this.fieldKeyPrefix,
    required this.onChanged,
    required this.onRemove,
  });

  final _SavingsDraftController controller;
  final String currency;
  final List<String> accountNames;
  final bool enabled;
  final bool canRemove;
  final String fieldKeyPrefix;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedAccount = accountNames.contains(controller.accountName)
        ? controller.accountName
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('$fieldKeyPrefix-name'),
                    controller: controller.nameController,
                    enabled: enabled,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Savings goal name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: 'Remove savings goal',
                  onPressed: enabled && canRemove ? onRemove : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _MoneyField(
              fieldKey: ValueKey('$fieldKeyPrefix-monthly'),
              controller: controller.monthlyController,
              currency: currency,
              label: 'Monthly savings',
              enabled: enabled,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: controller.targetCurrency,
              decoration: const InputDecoration(
                labelText: 'Target currency',
                border: OutlineInputBorder(),
              ),
              items: _currencyOptions
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(growable: false),
              onChanged: enabled
                  ? (value) {
                      if (value == null) return;
                      controller.targetCurrency = value;
                      controller.targetCurrencyTouched = true;
                      onChanged();
                    }
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: ValueKey('$fieldKeyPrefix-target'),
              controller: controller.targetController,
              enabled: enabled,
              onChanged: (_) => onChanged(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Target amount',
                prefixText: '${controller.targetCurrency} ',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: selectedAccount,
              decoration: const InputDecoration(
                labelText: 'Savings account',
                border: OutlineInputBorder(),
              ),
              items: accountNames
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(growable: false),
              onChanged: enabled && accountNames.isNotEmpty
                  ? (value) {
                      if (value == null) return;
                      controller.accountName = value;
                      onChanged();
                    }
                  : null,
            ),
            const SizedBox(height: AppSpacing.xs),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: controller.showInFamily,
              onChanged: enabled
                  ? (value) {
                      controller.showInFamily = value;
                      onChanged();
                    }
                  : null,
              title: const Text('Visible to household'),
              subtitle: const Text(
                'Show this savings goal in the family space.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountDraftController {
  _AccountDraftController({this.existingId, required this.currency});

  final String? existingId;
  final nameController = TextEditingController();
  final institutionController = TextEditingController();
  final balanceController = TextEditingController();
  String accountType = 'savings';
  String currency;

  void dispose() {
    nameController.dispose();
    institutionController.dispose();
    balanceController.dispose();
  }
}

class _AccountEditor extends StatelessWidget {
  const _AccountEditor({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.onRemove,
  });

  final _AccountDraftController controller;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller.nameController,
                enabled: enabled,
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(
                  labelText: 'Account name',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              tooltip: 'Remove account',
              onPressed: enabled ? onRemove : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: controller.institutionController,
          enabled: enabled,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            labelText: 'Bank or provider',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: controller.accountType,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: _accountTypeOptions
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(_accountTypeLabels[item] ?? item),
                      ),
                    )
                    .toList(growable: false),
                onChanged: enabled
                    ? (value) {
                        if (value == null) return;
                        controller.accountType = value;
                        onChanged();
                      }
                    : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: controller.currency,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(),
                ),
                items: _currencyOptions
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(growable: false),
                onChanged: enabled
                    ? (value) {
                        if (value == null) return;
                        controller.currency = value;
                        onChanged();
                      }
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: controller.balanceController,
          enabled: enabled,
          onChanged: (_) => onChanged(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Balance now',
            prefixText: '${controller.currency} ',
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.currency,
    required this.label,
    required this.enabled,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String currency;
  final String label;
  final bool enabled;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '$currency ',
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _DayField extends StatelessWidget {
  const _DayField({
    required this.controller,
    required this.label,
    required this.enabled,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _CommitmentDraftController {
  _CommitmentDraftController({this.existingId})
    : nameController = TextEditingController(),
      amountController = TextEditingController(),
      dayController = TextEditingController(text: '5');

  final String? existingId;
  final TextEditingController nameController;
  final TextEditingController amountController;
  final TextEditingController dayController;

  void dispose() {
    nameController.dispose();
    amountController.dispose();
    dayController.dispose();
  }
}

class _CommitmentSection extends StatelessWidget {
  const _CommitmentSection({
    required this.title,
    required this.description,
    required this.icon,
    required this.itemLabel,
    required this.itemHint,
    required this.addLabel,
    required this.currency,
    required this.drafts,
    required this.enabled,
    required this.sectionKeyPrefix,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final String description;
  final IconData icon;
  final String itemLabel;
  final String itemHint;
  final String addLabel;
  final String currency;
  final List<_CommitmentDraftController> drafts;
  final bool enabled;
  final String sectionKeyPrefix;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            TextButton.icon(
              key: ValueKey('$sectionKeyPrefix-add'),
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.add),
              label: Text(addLabel),
            ),
          ],
        ),
        Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var index = 0; index < drafts.length; index++) ...[
          _CommitmentDraftEditor(
            controller: drafts[index],
            currency: currency,
            itemLabel: itemLabel,
            itemHint: itemHint,
            enabled: enabled,
            canRemove: drafts.length > 1,
            fieldKeyPrefix: '$sectionKeyPrefix-$index',
            onRemove: () => onRemove(index),
          ),
          if (index < drafts.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _CommitmentDraftEditor extends StatelessWidget {
  const _CommitmentDraftEditor({
    required this.controller,
    required this.currency,
    required this.itemLabel,
    required this.itemHint,
    required this.enabled,
    required this.canRemove,
    required this.fieldKeyPrefix,
    required this.onRemove,
  });

  final _CommitmentDraftController controller;
  final String currency;
  final String itemLabel;
  final String itemHint;
  final bool enabled;
  final bool canRemove;
  final String fieldKeyPrefix;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('$fieldKeyPrefix-name'),
                    controller: controller.nameController,
                    enabled: enabled,
                    decoration: InputDecoration(
                      labelText: itemLabel,
                      hintText: itemHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: 'Remove item',
                  onPressed: enabled && canRemove ? onRemove : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _MoneyField(
                    fieldKey: ValueKey('$fieldKeyPrefix-amount'),
                    controller: controller.amountController,
                    currency: currency,
                    label: 'Amount',
                    enabled: enabled,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: _DayField(
                    fieldKey: ValueKey('$fieldKeyPrefix-day'),
                    controller: controller.dayController,
                    label: 'Day',
                    enabled: enabled,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _ReviewEmpty extends StatelessWidget {
  const _ReviewEmpty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Text(
        'Nothing selected yet. Finish setup now and add the rest later.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

class _ReviewItem {
  const _ReviewItem(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

class _OnboardingValidationException implements Exception {
  const _OnboardingValidationException(this.message);

  final String message;
}

String _titleCase(String value) {
  return value
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

double? _parseAmount(String value) {
  var normalized = value.trim().replaceAll(' ', '');
  if (normalized.isEmpty) {
    return null;
  }
  normalized = normalized.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (normalized.isEmpty ||
      normalized == '-' ||
      normalized == ',' ||
      normalized == '.') {
    return null;
  }

  final lastComma = normalized.lastIndexOf(',');
  final lastDot = normalized.lastIndexOf('.');
  final commaCount = ','.allMatches(normalized).length;
  final dotCount = '.'.allMatches(normalized).length;

  if (lastComma >= 0 && lastDot >= 0) {
    if (lastComma > lastDot) {
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    } else {
      normalized = normalized.replaceAll(',', '');
    }
  } else if (lastComma >= 0) {
    final fractionalDigits = normalized.length - lastComma - 1;
    if (commaCount > 1 ||
        (fractionalDigits == 3 && normalized.indexOf(',') == lastComma)) {
      normalized = normalized.replaceAll(',', '');
    } else {
      normalized = normalized.replaceAll(',', '.');
    }
  } else if (lastDot >= 0) {
    final fractionalDigits = normalized.length - lastDot - 1;
    if (dotCount > 1 ||
        (fractionalDigits == 3 && normalized.indexOf('.') == lastDot)) {
      normalized = normalized.replaceAll('.', '');
    }
  }

  return double.tryParse(normalized);
}
