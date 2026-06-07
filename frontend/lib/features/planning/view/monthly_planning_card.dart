import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/features/planning/models/monthly_category_catalog.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:flutter/material.dart';

class MonthlyPlanningCard extends StatefulWidget {
  const MonthlyPlanningCard({this.repository, this.refreshToken, super.key});

  final MonthlyPlanRepository? repository;
  final Object? refreshToken;

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
    if (widget.refreshToken != oldWidget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plan = await _repository.fetchPlan(month: _month);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _editPlan() async {
    final current = _plan;
    final updated = await showDialog<Map<String, double>>(
      context: context,
      builder: (context) => _BudgetDialog(
        categories: mergeMonthlyCategories(
          current?.categories.map((category) => category.category) ?? const [],
        ),
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
        currency: current?.currency ?? 'INR',
        budgets: updated,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
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
      return AppEmptyState(
        title: 'Plan this month',
        subtitle: 'Set category budgets and compare them with actual spend.',
        actionLabel: 'Set monthly plan',
        onAction: _editPlan,
      );
    }

    final remainingPositive = plan.totalRemaining >= 0;
    final progress = plan.totalBudget <= 0
        ? 0.0
        : (plan.totalActual / plan.totalBudget).clamp(0.0, 1.0);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Monthly plan',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Edit monthly plan',
                onPressed: _editPlan,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${plan.currency} ${plan.totalRemaining.abs().toStringAsFixed(2)} ${remainingPositive ? 'left' : 'over'}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppMoney.statusColor(context, positive: remainingPositive),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text(
            '${plan.currency} ${plan.totalActual.toStringAsFixed(2)} spent of ${plan.currency} ${plan.totalBudget.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 12),
          ...plan.categories
              .take(5)
              .map(
                (category) =>
                    _BudgetRow(category: category, currency: plan.currency),
              ),
        ],
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.category, required this.currency});

  final MonthlyPlanCategory category;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final color = AppMoney.statusColor(
      context,
      positive: !category.overBudget,
      neutral: category.budget <= 0,
    );
    final progress = category.budget <= 0
        ? 0.0
        : category.progress.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(category.category)),
              Text(
                '$currency ${category.actual.toStringAsFixed(0)} / ${category.budget.toStringAsFixed(0)}',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: progress, color: color),
        ],
      ),
    );
  }
}

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.categories, required this.initialBudgets});

  final List<String> categories;
  final Map<String, double> initialBudgets;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final List<String> _categories;
  late final Map<String, TextEditingController> _controllers;
  late final TextEditingController _newCategoryController;

  @override
  void initState() {
    super.initState();
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
      final value = double.tryParse(controller.text.trim()) ?? 0;
      if (value > 0) {
        budgets[category] = value;
      }
    }
    Navigator.of(context).pop(budgets);
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
              for (final category in _categories) ...[
                TextField(
                  controller: _controllers[category],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: category,
                    prefixText: 'INR ',
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
