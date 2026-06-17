import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/features/onboarding/view/monthly_plan_onboarding_page.dart';
import 'package:expense_tracker/features/planning/models/monthly_category_catalog.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:flutter/material.dart';

const _planCurrencyOptions = <String>['INR', 'USD', 'EUR', 'GBP', 'NOK'];

typedef RecordPlannedPayment =
    Future<bool> Function(
      String category, {
      required double amount,
      required String currency,
    });

class MonthlyPlanningCard extends StatefulWidget {
  const MonthlyPlanningCard({
    this.repository,
    this.refreshToken,
    this.groupId,
    this.title = 'Monthly plan',
    this.onAddExpenseForCategory,
    this.onRecordPlannedPayment,
    this.onReviewCategory,
    this.onPlanLoaded,
    super.key,
  });

  final MonthlyPlanRepository? repository;
  final Object? refreshToken;
  final String? groupId;
  final String title;
  final ValueChanged<String>? onAddExpenseForCategory;
  final RecordPlannedPayment? onRecordPlannedPayment;
  final ValueChanged<String>? onReviewCategory;
  final ValueChanged<MonthlyPlan>? onPlanLoaded;

  @override
  State<MonthlyPlanningCard> createState() => _MonthlyPlanningCardState();
}

class _MonthlyPlanningCardState extends State<MonthlyPlanningCard> {
  late final MonthlyPlanRepository _repository;
  late final bool _ownsRepository;
  MonthlyPlan? _plan;
  bool _loading = true;
  String? _error;

  String get _month {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MonthlyPlanRepository();
    _ownsRepository = widget.repository == null;
    _load();
  }

  @override
  void dispose() {
    if (_ownsRepository) {
      _repository.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MonthlyPlanningCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken ||
        widget.groupId != oldWidget.groupId) {
      _load(showLoading: widget.groupId != oldWidget.groupId);
    }
  }

  Future<void> _load({bool showLoading = true}) async {
    setState(() {
      _loading = showLoading || _plan == null;
      _error = null;
    });
    try {
      final plan = await _repository.fetchPlan(
        month: _month,
        groupId: widget.groupId,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _loading = false;
      });
      widget.onPlanLoaded?.call(plan);
    } catch (error) {
      if (!mounted) return;
      if (!showLoading && _plan != null) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _editPlan() async {
    final current = _plan;
    final updated = await showDialog<_BudgetDialogResult>(
      context: context,
      builder: (context) => _BudgetDialog(
        categories: mergeMonthlyCategories(
          current?.categories.map((category) => category.category) ?? const [],
        ),
        initialCurrency: current?.currency ?? 'INR',
        initialBudgets: current?.budgetsByCategory ?? const {},
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plan = await _repository.savePlan(
        month: _month,
        groupId: widget.groupId,
        currency: updated.currency,
        budgets: updated.budgets,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _loading = false;
      });
      widget.onPlanLoaded?.call(plan);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openGuidedSetup() async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (context) =>
            const MonthlyPlanOnboardingPage(completeOnFinish: false),
      ),
    );
    if (completed == true && mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppCard(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading monthly plan...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return AppEmptyState(
        title: 'Monthly plan unavailable',
        subtitle: _error,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    final plan = _plan;
    if (plan == null || plan.totalBudget <= 0) {
      final scoped = widget.groupId?.trim().isNotEmpty == true;
      return AppEmptyState(
        title: scoped ? widget.title : 'Plan this month',
        subtitle: scoped
            ? 'Set category budgets for this household and compare them with shared spend.'
            : 'Set category budgets and compare them with actual spend.',
        actionLabel: scoped ? 'Set household plan' : 'Set monthly plan',
        onAction: scoped ? _editPlan : _openGuidedSetup,
      );
    }

    final outstandingLoanAmount = _outstandingLoanAmount(plan);
    final plannedCostAmount = _plannedCostAmount(plan);
    final plannedSavingsAmount = _plannedPositiveAmount(plan);
    final hasPlannedCosts = plannedCostAmount > 0.005;
    final isOverPlan = plan.totalRemaining < -0.005;
    final colors = Theme.of(context).colorScheme;
    final headlineText = isOverPlan
        ? '${plan.currency} ${plan.totalRemaining.abs().toStringAsFixed(2)} over plan'
        : hasPlannedCosts
        ? '${plan.currency} ${plannedCostAmount.toStringAsFixed(2)} planned costs'
        : '${plan.currency} ${plannedSavingsAmount.toStringAsFixed(2)} planned savings';
    final headlineColor = isOverPlan || hasPlannedCosts
        ? colors.error
        : AppMoney.statusColor(context, positive: true);
    final plannedCostText = hasPlannedCosts
        ? '${plan.currency} ${plannedCostAmount.toStringAsFixed(2)} planned costs'
        : '${plan.currency} ${plan.totalBudget.toStringAsFixed(2)} planned';
    final savingsText = plannedSavingsAmount > 0.005 && hasPlannedCosts
        ? ' + ${plan.currency} ${plannedSavingsAmount.toStringAsFixed(2)} planned savings'
        : '';
    final progress = plan.totalBudget <= 0
        ? 0.0
        : (plan.totalActual / plan.totalBudget).clamp(0.0, 1.0);
    final scoped = widget.groupId?.trim().isNotEmpty == true;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (!scoped) ...[
                TextButton.icon(
                  onPressed: _openGuidedSetup,
                  icon: const Icon(Icons.checklist_outlined),
                  label: const Text('Complete setup'),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                tooltip: 'Edit monthly plan',
                onPressed: _editPlan,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            headlineText,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: headlineColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (outstandingLoanAmount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${plan.currency} ${outstandingLoanAmount.toStringAsFixed(2)} due in loans',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text(
            '${plan.currency} ${plan.totalActual.toStringAsFixed(2)} spent of $plannedCostText$savingsText',
          ),
          if (plan.excludedExpenseCount > 0 ||
              plan.excludedActualsByCurrency.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PlanCoverageNotice(plan: plan),
          ],
          if (widget.onAddExpenseForCategory != null ||
              widget.onReviewCategory != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.onReviewCategory != null
                  ? 'Tap a category to review it. Use + to log a matching expense.'
                  : 'Use + next to a category to log a matching expense.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...plan.categories
              .take(5)
              .map(
                (category) => _BudgetRow(
                  category: category,
                  currency: plan.currency,
                  onAddExpense: widget.onAddExpenseForCategory == null
                      ? null
                      : () =>
                            widget.onAddExpenseForCategory!(category.category),
                  onRecordPayment: widget.onRecordPlannedPayment == null
                      ? null
                      : () => _recordPlannedPayment(category),
                  onReview: widget.onReviewCategory == null
                      ? null
                      : () => widget.onReviewCategory!(category.category),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _recordPlannedPayment(MonthlyPlanCategory category) async {
    final callback = widget.onRecordPlannedPayment;
    if (callback == null) return;
    final remaining = (category.budget - category.actual).clamp(
      0.0,
      double.infinity,
    );
    final saved = await callback(
      category.category,
      amount: remaining > 0.005 ? remaining : category.budget,
      currency: _plan?.currency ?? 'INR',
    );
    if (saved && mounted) {
      await _load(showLoading: false);
    }
  }
}

class _PlanCoverageNotice extends StatelessWidget {
  const _PlanCoverageNotice({required this.plan});

  final MonthlyPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = plan.excludedExpenseCount;
    final expenseLabel = count == 1 ? 'expense' : 'expenses';
    final title = count > 0
        ? '$count $expenseLabel not counted in ${plan.currency} actuals'
        : 'Some expenses are not counted in ${plan.currency} actuals';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.error.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: colors.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (plan.excludedActualsByCurrency.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Outside plan currency: ${AppMoney.formatCurrencyAmounts(plan.excludedActualsByCurrency)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.category,
    required this.currency,
    this.onAddExpense,
    this.onRecordPayment,
    this.onReview,
  });

  final MonthlyPlanCategory category;
  final String currency;
  final VoidCallback? onAddExpense;
  final VoidCallback? onRecordPayment;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final obligation = _isLoanCategory(category.category);
    final positivePlanCategory = _isPositivePlanCategory(category.category);
    final colors = Theme.of(context).colorScheme;
    final outstandingAmount = obligation
        ? (category.budget - category.actual).clamp(0.0, double.infinity)
        : 0.0;
    final remainingCost = (category.budget - category.actual).clamp(
      0.0,
      double.infinity,
    );
    final canRecordPayment =
        onRecordPayment != null &&
        !positivePlanCategory &&
        remainingCost > 0.005 &&
        category.budget > 0;
    final color = category.budget <= 0
        ? colors.outline
        : positivePlanCategory
        ? AppMoney.statusColor(context, positive: true)
        : colors.error;
    final progress = category.budget <= 0
        ? 0.0
        : category.progress.clamp(0.0, 1.0);
    final summaryText = obligation
        ? outstandingAmount > 0.005
              ? '$currency ${outstandingAmount.toStringAsFixed(0)} due'
              : '$currency ${category.actual.toStringAsFixed(0)} paid'
        : positivePlanCategory
        ? '$currency ${category.budget.toStringAsFixed(0)} target'
        : category.actual > 0.005
        ? '$currency ${category.actual.toStringAsFixed(0)} spent / ${category.budget.toStringAsFixed(0)} planned'
        : '$currency ${category.budget.toStringAsFixed(0)} planned';
    final content = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(category.category)),
              Text(
                summaryText,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
              if (onAddExpense != null) ...[
                const SizedBox(width: 4),
                SizedBox(
                  height: 32,
                  width: 32,
                  child: IconButton(
                    tooltip: 'Add ${category.category} expense',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onPressed: onAddExpense,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ),
              ],
              if (canRecordPayment) ...[
                const SizedBox(width: 4),
                SizedBox(
                  height: 32,
                  width: 32,
                  child: IconButton(
                    tooltip: 'Mark ${category.category} paid previously',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onPressed: onRecordPayment,
                    icon: const Icon(Icons.history_toggle_off_outlined),
                  ),
                ),
              ],
              if (onReview != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: progress, color: color),
          if (obligation) ...[
            const SizedBox(height: 4),
            Text(
              'Paid $currency ${category.actual.toStringAsFixed(0)} of ${category.budget.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          if (category.excludedExpenseCount > 0 ||
              category.excludedActualsByCurrency.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Not counted: ${_excludedActualsText(category)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
    if (onReview == null) {
      return content;
    }
    return InkWell(
      onTap: onReview,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}

String _excludedActualsText(MonthlyPlanCategory category) {
  if (category.excludedActualsByCurrency.isNotEmpty) {
    return AppMoney.formatCurrencyAmounts(category.excludedActualsByCurrency);
  }
  final count = category.excludedExpenseCount;
  return '$count ${count == 1 ? 'expense' : 'expenses'}';
}

double _outstandingLoanAmount(MonthlyPlan plan) {
  return plan.categories.fold<double>(0, (sum, category) {
    if (!_isLoanCategory(category.category)) {
      return sum;
    }
    return sum +
        (category.budget - category.actual).clamp(0.0, double.infinity);
  });
}

bool _isLoanCategory(String category) {
  final normalized = category.trim().toLowerCase();
  return normalized.contains('loan') || normalized.contains('emi');
}

double _plannedCostAmount(MonthlyPlan plan) {
  return plan.categories.fold<double>(0, (sum, category) {
    if (_isPositivePlanCategory(category.category)) {
      return sum;
    }
    return sum + category.budget;
  });
}

double _plannedPositiveAmount(MonthlyPlan plan) {
  return plan.categories.fold<double>(0, (sum, category) {
    if (!_isPositivePlanCategory(category.category)) {
      return sum;
    }
    return sum + category.budget;
  });
}

bool _isPositivePlanCategory(String category) {
  final normalized = category.trim().toLowerCase();
  return normalized.contains('saving') ||
      normalized.contains('investment') ||
      normalized.contains('sip') ||
      normalized.contains('fixed deposit');
}

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({
    required this.categories,
    required this.initialCurrency,
    required this.initialBudgets,
  });

  final List<String> categories;
  final String initialCurrency;
  final Map<String, double> initialBudgets;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final List<String> _categories;
  late final Map<String, TextEditingController> _controllers;
  late final TextEditingController _newCategoryController;
  late String _currency;

  @override
  void initState() {
    super.initState();
    _currency = _normalizePlanCurrency(widget.initialCurrency);
    _categories = mergeMonthlyCategories([
      ...widget.categories,
      ...widget.initialBudgets.keys,
    ]).toList();
    _controllers = {
      for (final category in _categories)
        category: TextEditingController(
          text: (widget.initialBudgets[category] ?? 0) > 0
              ? widget.initialBudgets[category]!.toStringAsFixed(0)
              : '',
        ),
    };
    _newCategoryController = TextEditingController();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _newCategoryController.dispose();
    super.dispose();
  }

  void _addCategory() {
    final label = _newCategoryController.text.trim();
    if (label.isEmpty) return;
    final existing = _categories.any(
      (category) => category.toLowerCase() == label.toLowerCase(),
    );
    if (existing) {
      _newCategoryController.clear();
      return;
    }
    setState(() {
      _categories.add(label);
      _controllers[label] = TextEditingController();
      _newCategoryController.clear();
    });
  }

  void _save() {
    final budgets = <String, double>{};
    for (final category in _categories) {
      final controller = _controllers[category];
      if (controller == null) continue;
      final value = _parseBudgetAmount(controller.text) ?? 0;
      if (value > 0) {
        budgets[category] = value;
      }
    }
    Navigator.of(
      context,
    ).pop(_BudgetDialogResult(currency: _currency, budgets: budgets));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Monthly plan'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: const InputDecoration(
                  labelText: 'Plan currency',
                  border: OutlineInputBorder(),
                ),
                items: _planCurrencyOptions
                    .map(
                      (currency) => DropdownMenuItem<String>(
                        value: currency,
                        child: Text(currency),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _currency = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              for (final category in _categories) ...[
                TextField(
                  controller: _controllers[category],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: category,
                    prefixText: '$_currency ',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newCategoryController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Add category',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addCategory(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Add category',
                    onPressed: _addCategory,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save plan')),
      ],
    );
  }
}

String _normalizePlanCurrency(String value) {
  final normalized = value.trim().toUpperCase();
  return _planCurrencyOptions.contains(normalized) ? normalized : 'INR';
}

class _BudgetDialogResult {
  const _BudgetDialogResult({required this.currency, required this.budgets});

  final String currency;
  final Map<String, double> budgets;
}

double? _parseBudgetAmount(String value) {
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
