import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:expense_tracker/core/ui/app_page_container.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/onboarding/repositories/onboarding_setup_writer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
  final _salaryAmountController = TextEditingController();
  final _salaryDayController = TextEditingController(text: '25');
  final _rentAmountController = TextEditingController();
  final _rentDayController = TextEditingController(text: '1');
  final _loanNameController = TextEditingController(text: 'Car loan');
  final _loanLenderController = TextEditingController();
  final _loanPrincipalController = TextEditingController();
  final _loanEmiController = TextEditingController();
  final _loanInterestController = TextEditingController();
  final _loanMonthsController = TextEditingController();
  final _loanDueDayController = TextEditingController(text: '18');
  final _groceriesController = TextEditingController();
  final _utilitiesController = TextEditingController();
  final _utilitiesDayController = TextEditingController(text: '5');
  final _subscriptionsController = TextEditingController();
  final _subscriptionsDayController = TextEditingController(text: '5');
  final _membershipsController = TextEditingController();
  final _membershipsDayController = TextEditingController(text: '5');
  final _transportController = TextEditingController();
  final _savingsNameController = TextEditingController(text: 'India savings');
  final _savingsMonthlyController = TextEditingController();
  final _savingsTargetController = TextEditingController();

  var _stepIndex = 0;
  var _currency = 'NOK';
  var _loanRateType = 'floating';
  var _loanType = 'Car';
  var _savingsTargetCurrency = 'INR';
  var _savingsAccountName = '';
  var _showSavingsInFamily = false;
  var _saving = false;
  String? _message;

  _SetupStep get _step => _setupSteps[_stepIndex];

  @override
  void initState() {
    super.initState();
    _setupWriter = widget.setupWriter ?? ApiOnboardingSetupWriter();
    _ownsSetupWriter = widget.setupWriter == null;
    _accounts.add(_AccountDraftController(currency: _currency));
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
    _loanNameController.dispose();
    _loanLenderController.dispose();
    _loanPrincipalController.dispose();
    _loanEmiController.dispose();
    _loanInterestController.dispose();
    _loanMonthsController.dispose();
    _loanDueDayController.dispose();
    _groceriesController.dispose();
    _utilitiesController.dispose();
    _utilitiesDayController.dispose();
    _subscriptionsController.dispose();
    _subscriptionsDayController.dispose();
    _membershipsController.dispose();
    _membershipsDayController.dispose();
    _transportController.dispose();
    _savingsNameController.dispose();
    _savingsMonthlyController.dispose();
    _savingsTargetController.dispose();
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
        await _setupWriter.createFinancialAccount(
          name: name,
          institution: account.institutionController.text.trim(),
          accountType: account.accountType,
          currency: account.currency,
          openingBalance: _amountValue(account.balanceController),
        );
      }

      final salaryAmount = _amountValue(_salaryAmountController);
      if (salaryAmount > 0) {
        await _setupWriter.createRecurringTemplate(
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
        await _setupWriter.createRecurringTemplate(
          title: 'Rent and housing',
          kind: 'expense',
          amount: rentAmount,
          category: 'Rent and housing',
          currency: _currency,
          dayOfMonth: _dayValue(_rentDayController, 'Housing due day'),
        );
      }

      final loanPrincipal = _amountValue(_loanPrincipalController);
      final loanEmi = _amountValue(_loanEmiController);
      if (loanPrincipal > 0 || loanEmi > 0) {
        if (loanPrincipal <= 0 || loanEmi <= 0) {
          throw const _OnboardingValidationException(
            'Loan needs remaining principal and EMI, or skip the loan step.',
          );
        }
        budgets['Loans / EMI'] = loanEmi;
        await _setupWriter.createLoan(
          name: _loanNameController.text.trim().isEmpty
              ? 'Loan'
              : _loanNameController.text.trim(),
          lender: _loanLenderController.text.trim(),
          loanType: _loanType,
          principalAmount: loanPrincipal,
          emiAmount: loanEmi,
          currency: _currency,
          interestRate: _amountValue(_loanInterestController),
          rateType: _loanRateType,
          remainingEmis: _intValue(_loanMonthsController),
          dueDay: _dayValue(_loanDueDayController, 'Loan due day'),
        );
      }

      _addBudget(budgets, 'Groceries', _groceriesController);
      await _addCommitment(
        budgets,
        title: 'Utilities',
        category: 'Utilities',
        amountController: _utilitiesController,
        dayController: _utilitiesDayController,
      );
      await _addCommitment(
        budgets,
        title: 'Subscriptions',
        category: 'Subscriptions',
        amountController: _subscriptionsController,
        dayController: _subscriptionsDayController,
      );
      await _addCommitment(
        budgets,
        title: 'Memberships',
        category: 'Memberships',
        amountController: _membershipsController,
        dayController: _membershipsDayController,
      );
      _addBudget(budgets, 'Transport', _transportController);

      final savingsMonthly = _amountValue(_savingsMonthlyController);
      if (savingsMonthly > 0) {
        budgets['Savings'] = savingsMonthly;
        final explicitTarget = _amountValue(_savingsTargetController);
        await _setupWriter.createSavingsGoal(
          name: _savingsNameController.text.trim().isEmpty
              ? 'Savings'
              : _savingsNameController.text.trim(),
          targetAmount: explicitTarget > 0
              ? explicitTarget
              : savingsMonthly * 12,
          targetCurrency: _savingsTargetCurrency,
          sourceCurrency: _currency,
          monthlyTargetAmount: savingsMonthly,
          startMonth: month,
          accountName: _savingsAccountName,
          familyVisibility: _showSavingsInFamily ? 'family' : 'private',
        );
      }

      if (budgets.isNotEmpty) {
        await _setupWriter.saveMonthlyPlan(
          month: month,
          currency: _currency,
          budgets: budgets,
        );
      }
      if (!mounted) return;
      if (widget.completeOnFinish) {
        await context.read<AuthCubit>().completeOnboarding();
      } else {
        Navigator.of(context).pop(true);
      }
    });
  }

  Future<void> _addCommitment(
    Map<String, double> budgets, {
    required String title,
    required String category,
    required TextEditingController amountController,
    required TextEditingController dayController,
  }) async {
    final amount = _amountValue(amountController);
    if (amount <= 0) return;
    budgets[category] = amount;
    await _setupWriter.createRecurringTemplate(
      title: title,
      kind: 'expense',
      amount: amount,
      category: category,
      currency: _currency,
      dayOfMonth: _dayValue(dayController, '$title due day'),
    );
  }

  void _addBudget(
    Map<String, double> budgets,
    String category,
    TextEditingController controller,
  ) {
    final amount = _amountValue(controller);
    if (amount > 0) {
      budgets[category] = amount;
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
        _savingsAccountName = '';
        break;
      case _SetupStep.salary:
        _salaryAmountController.clear();
        break;
      case _SetupStep.housing:
        _rentAmountController.clear();
        break;
      case _SetupStep.loans:
        _loanPrincipalController.clear();
        _loanEmiController.clear();
        _loanInterestController.clear();
        _loanMonthsController.clear();
        break;
      case _SetupStep.groceries:
        _groceriesController.clear();
        break;
      case _SetupStep.commitments:
        _utilitiesController.clear();
        _subscriptionsController.clear();
        _membershipsController.clear();
        break;
      case _SetupStep.transport:
        _transportController.clear();
        break;
      case _SetupStep.savings:
        _savingsMonthlyController.clear();
        _savingsTargetController.clear();
        break;
      case _SetupStep.review:
        break;
    }
  }

  void _syncSavingsAccountSelection() {
    final accountNames = _accountNames;
    if (accountNames.isEmpty) {
      _savingsAccountName = '';
      return;
    }
    if (!accountNames.contains(_savingsAccountName)) {
      _savingsAccountName = accountNames.first;
    }
  }

  List<String> get _accountNames {
    return _accounts
        .map((account) => account.nameController.text.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  double _amountValue(TextEditingController controller) {
    return double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
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

  String get _stepTitle {
    return switch (_step) {
      _SetupStep.currency => 'Currency',
      _SetupStep.accounts => 'Bank accounts',
      _SetupStep.salary => 'Salary',
      _SetupStep.housing => 'Rent and housing',
      _SetupStep.loans => 'Loans',
      _SetupStep.groceries => 'Groceries',
      _SetupStep.commitments => 'Bills',
      _SetupStep.transport => 'Transport',
      _SetupStep.savings => 'Savings',
      _SetupStep.review => 'Review',
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
        child: AppPageContainer(
          maxWidth: 640,
          children: [
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: _saving || _stepIndex == 0 ? null : _previousStep,
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
                  tooltip: 'Skip setup',
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
            const SizedBox(height: AppSpacing.lg),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(key: ValueKey(_step), child: _buildStep()),
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
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving || _step == _SetupStep.review
                        ? null
                        : _skipStep,
                    icon: const Icon(Icons.skip_next_outlined),
                    label: const Text('Skip this step'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _nextStep,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _step == _SetupStep.review
                                ? Icons.check
                                : Icons.arrow_forward,
                          ),
                    label: Text(
                      _step == _SetupStep.review ? 'Finish setup' : 'Next',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
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
                    _currency = value;
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
            onChanged: () => setState(_syncSavingsAccountSelection),
            onRemove: _accounts.length == 1
                ? null
                : () {
                    setState(() {
                      _accounts.removeAt(index).dispose();
                      _syncSavingsAccountSelection();
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
      children: [
        TextField(
          controller: _loanNameController,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Loan name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _loanLenderController,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Lender',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _loanType,
          decoration: const InputDecoration(
            labelText: 'Loan type',
            border: OutlineInputBorder(),
          ),
          items: const ['Car', 'Home', 'Personal', 'Education', 'Other']
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(growable: false),
          onChanged: _saving
              ? null
              : (value) {
                  if (value != null) setState(() => _loanType = value);
                },
        ),
        const SizedBox(height: AppSpacing.md),
        _MoneyField(
          controller: _loanPrincipalController,
          currency: _currency,
          label: 'Remaining principal',
          enabled: !_saving,
        ),
        const SizedBox(height: AppSpacing.md),
        _MoneyField(
          controller: _loanEmiController,
          currency: _currency,
          label: 'Monthly EMI',
          enabled: !_saving,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _loanInterestController,
                enabled: !_saving,
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
                initialValue: _loanRateType,
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
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _loanRateType = value);
                        }
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _loanMonthsController,
                enabled: !_saving,
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
                controller: _loanDueDayController,
                label: 'EMI day',
                enabled: !_saving,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _groceriesStep() {
    return _MoneyField(
      controller: _groceriesController,
      currency: _currency,
      label: 'Monthly grocery budget',
      enabled: !_saving,
    );
  }

  Widget _commitmentsStep() {
    return Column(
      children: [
        _CommitmentRow(
          label: 'Utilities',
          currency: _currency,
          amountController: _utilitiesController,
          dayController: _utilitiesDayController,
          enabled: !_saving,
        ),
        const SizedBox(height: AppSpacing.md),
        _CommitmentRow(
          label: 'Subscriptions',
          currency: _currency,
          amountController: _subscriptionsController,
          dayController: _subscriptionsDayController,
          enabled: !_saving,
        ),
        const SizedBox(height: AppSpacing.md),
        _CommitmentRow(
          label: 'Memberships',
          currency: _currency,
          amountController: _membershipsController,
          dayController: _membershipsDayController,
          enabled: !_saving,
        ),
      ],
    );
  }

  Widget _transportStep() {
    return _MoneyField(
      controller: _transportController,
      currency: _currency,
      label: 'Monthly transport budget',
      enabled: !_saving,
    );
  }

  Widget _savingsStep() {
    final accountNames = _accountNames;
    return Column(
      children: [
        TextField(
          controller: _savingsNameController,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Savings goal name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _MoneyField(
          controller: _savingsMonthlyController,
          currency: _currency,
          label: 'Monthly savings',
          enabled: !_saving,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _savingsTargetCurrency,
          decoration: const InputDecoration(
            labelText: 'Target currency',
            border: OutlineInputBorder(),
          ),
          items: _currencyOptions
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(growable: false),
          onChanged: _saving
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _savingsTargetCurrency = value);
                  }
                },
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _savingsTargetController,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Target amount',
            prefixText: '$_savingsTargetCurrency ',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: accountNames.contains(_savingsAccountName)
              ? _savingsAccountName
              : null,
          decoration: const InputDecoration(
            labelText: 'Savings account',
            border: OutlineInputBorder(),
          ),
          items: accountNames
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(growable: false),
          onChanged: _saving || accountNames.isEmpty
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _savingsAccountName = value);
                  }
                },
        ),
        const SizedBox(height: AppSpacing.sm),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _showSavingsInFamily,
          onChanged: _saving
              ? null
              : (value) => setState(() => _showSavingsInFamily = value),
          title: const Text('Show in family'),
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
    final loanEmi = _amountValue(_loanEmiController);
    if (loanEmi > 0) {
      rows.add(
        _ReviewItem(
          Icons.request_quote_outlined,
          'Loan EMI',
          '$_currency ${loanEmi.toStringAsFixed(0)}',
        ),
      );
    }
    for (final item in [
      (Icons.shopping_basket_outlined, 'Groceries', _groceriesController),
      (Icons.receipt_long_outlined, 'Utilities', _utilitiesController),
      (Icons.subscriptions_outlined, 'Subscriptions', _subscriptionsController),
      (Icons.card_membership_outlined, 'Memberships', _membershipsController),
      (Icons.directions_car_outlined, 'Transport', _transportController),
      (Icons.savings_outlined, 'Savings', _savingsMonthlyController),
    ]) {
      final amount = _amountValue(item.$3);
      if (amount > 0) {
        rows.add(
          _ReviewItem(
            item.$1,
            item.$2,
            '$_currency ${amount.toStringAsFixed(0)}',
          ),
        );
      }
    }
    return rows;
  }
}

class _AccountDraftController {
  _AccountDraftController({required this.currency});

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
  });

  final TextEditingController controller;
  final String currency;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
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
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
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

class _CommitmentRow extends StatelessWidget {
  const _CommitmentRow({
    required this.label,
    required this.currency,
    required this.amountController,
    required this.dayController,
    required this.enabled,
  });

  final String label;
  final String currency;
  final TextEditingController amountController;
  final TextEditingController dayController;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _MoneyField(
            controller: amountController,
            currency: currency,
            label: label,
            enabled: enabled,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 2,
          child: _DayField(
            controller: dayController,
            label: 'Day',
            enabled: enabled,
          ),
        ),
      ],
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
        'Nothing selected.',
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
