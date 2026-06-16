import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:expense_tracker/core/ui/app_page_container.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _currencyOptions = <String>['NOK', 'INR', 'USD', 'EUR', 'GBP'];
const _starterCategories = <String>[
  'Groceries',
  'Rent and housing',
  'Utilities',
  'Transport',
  'Savings',
];

class MonthlyPlanOnboardingPage extends StatefulWidget {
  const MonthlyPlanOnboardingPage({this.repository, super.key});

  final MonthlyPlanRepository? repository;

  @override
  State<MonthlyPlanOnboardingPage> createState() =>
      _MonthlyPlanOnboardingPageState();
}

class _MonthlyPlanOnboardingPageState extends State<MonthlyPlanOnboardingPage> {
  late final MonthlyPlanRepository _repository;
  late final bool _ownsRepository;
  late final Map<String, TextEditingController> _controllers;
  var _currency = 'NOK';
  var _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MonthlyPlanRepository();
    _ownsRepository = widget.repository == null;
    _controllers = {
      for (final category in _starterCategories)
        category: TextEditingController(),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    if (_ownsRepository) {
      _repository.dispose();
    }
    super.dispose();
  }

  Future<void> _savePlan() async {
    final budgets = <String, double>{};
    for (final entry in _controllers.entries) {
      final amount = double.tryParse(entry.value.text.trim()) ?? 0;
      if (amount > 0) {
        budgets[entry.key] = amount;
      }
    }
    if (budgets.isEmpty) {
      setState(() => _message = 'Add at least one amount, or skip for now.');
      return;
    }
    await _run(() async {
      await _repository.savePlan(
        month: _monthKey(DateTime.now()),
        currency: _currency,
        budgets: budgets,
      );
      if (!mounted) return;
      await context.read<AuthCubit>().completeOnboarding();
    });
  }

  Future<void> _skip() {
    return _run(() => context.read<AuthCubit>().completeOnboarding());
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Could not save setup. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _monthKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: AppPageContainer(
          maxWidth: 560,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 44,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Set this month',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Start with your regular expenses and savings.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(
                labelText: 'Plan currency',
                border: OutlineInputBorder(),
              ),
              items: _currencyOptions
                  .map(
                    (currency) => DropdownMenuItem<String>(
                      value: currency,
                      child: Text(currency),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _currency = value);
                      }
                    },
            ),
            const SizedBox(height: AppSpacing.md),
            for (final entry in _controllers.entries) ...[
              TextField(
                controller: entry.value,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: entry.key,
                  prefixText: '$_currency ',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _saving ? null : _savePlan,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Save monthly plan'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _saving ? null : _skip,
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}
