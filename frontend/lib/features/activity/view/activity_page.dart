import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

enum _ActivityRange { week, month, year }

class _ActivityPageState extends State<ActivityPage> {
  ExpenseRepository? _repository;
  List<Expense> _expenses = const [];
  _ActivityRange _range = _ActivityRange.week;
  bool _loadedRepository = false;
  bool _loadingExpenses = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedRepository) return;
    _loadedRepository = true;
    _repository = context.read<ExpenseRepository?>();
    _refreshExpenses();
  }

  Future<void> _refreshExpenses() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() => _loadingExpenses = true);
    try {
      await repository.refresh();
      if (!mounted) return;
      setState(() => _expenses = repository.getExpenses());
    } catch (_) {
      if (!mounted) return;
      setState(() => _expenses = repository.getExpenses());
    } finally {
      if (mounted) {
        setState(() => _loadingExpenses = false);
      }
    }
  }

  DateTime _startForRange(_ActivityRange range, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (range) {
      _ActivityRange.week => today.subtract(const Duration(days: 6)),
      _ActivityRange.month => DateTime(now.year, now.month),
      _ActivityRange.year => DateTime(now.year),
    };
  }

  DateTime _previousStartForRange(_ActivityRange range, DateTime start) {
    return switch (range) {
      _ActivityRange.week => start.subtract(const Duration(days: 7)),
      _ActivityRange.month => DateTime(start.year, start.month - 1),
      _ActivityRange.year => DateTime(start.year - 1),
    };
  }

  DateTime _periodEndForRange(_ActivityRange range, DateTime start) {
    return switch (range) {
      _ActivityRange.week => start.add(const Duration(days: 7)),
      _ActivityRange.month => DateTime(start.year, start.month + 1),
      _ActivityRange.year => DateTime(start.year + 1),
    };
  }

  List<Expense> _expensesInPeriod(DateTime start, DateTime end) {
    return _expenses
        .where((expense) {
          final date = expense.createdAt;
          return !date.isBefore(start) && date.isBefore(end);
        })
        .toList(growable: false);
  }

  List<AppChartPoint> _trendPoints(DateTime start, DateTime end) {
    switch (_range) {
      case _ActivityRange.week:
        return List.generate(7, (index) {
          final day = start.add(Duration(days: index));
          final next = day.add(const Duration(days: 1));
          return AppChartPoint(
            label: _weekdayLabel(day),
            value: _expensesInPeriod(day, next).totalAmount,
          );
        });
      case _ActivityRange.month:
        final points = <AppChartPoint>[];
        var cursor = start;
        var bucket = 1;
        while (cursor.isBefore(end)) {
          final next = cursor.add(const Duration(days: 7));
          points.add(
            AppChartPoint(
              label: 'W$bucket',
              value: _expensesInPeriod(cursor, next).totalAmount,
            ),
          );
          cursor = next;
          bucket += 1;
        }
        return points;
      case _ActivityRange.year:
        return List.generate(12, (index) {
          final month = DateTime(start.year, index + 1);
          final next = DateTime(start.year, index + 2);
          return AppChartPoint(
            label: _monthLabel(month),
            value: _expensesInPeriod(month, next).totalAmount,
          );
        });
    }
  }

  List<_CategoryTotal> _categoryTotals(List<Expense> expenses) {
    final totals = <String, _CategoryTotal>{};
    for (final expense in expenses) {
      final label = (expense.category ?? '').trim().isEmpty
          ? 'Other'
          : expense.category!.trim();
      final current = totals[label] ?? _CategoryTotal.empty(label);
      totals[label] = current.add(expense.amount);
    }
    final values = totals.values.toList(growable: false)
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return values;
  }

  String _weekdayLabel(DateTime day) {
    return const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.weekday - 1];
  }

  String _monthLabel(DateTime month) {
    return const [
      'J',
      'F',
      'M',
      'A',
      'M',
      'J',
      'J',
      'A',
      'S',
      'O',
      'N',
      'D',
    ][month.month - 1];
  }

  String _rangeLabel(_ActivityRange range) {
    return switch (range) {
      _ActivityRange.week => 'Week',
      _ActivityRange.month => 'Month',
      _ActivityRange.year => 'Year',
    };
  }

  String _comparisonLabel(double current, double previous) {
    final range = _rangeLabel(_range).toLowerCase();
    if (previous <= 0 && current <= 0) {
      return 'No change vs last $range';
    }
    if (previous <= 0) {
      return '+100% vs last $range';
    }
    final delta = ((current - previous) / previous) * 100;
    final sign = delta >= 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(0)}% vs last $range';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardSnapshotCubit, DashboardSnapshotState>(
      builder: (context, state) {
        if (state is DashboardSnapshotFailure) {
          return SelectableErrorMessage(state.message);
        }
        if (state is! DashboardSnapshotLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final now = DateTime.now();
        final start = _startForRange(_range, now);
        final end = _periodEndForRange(_range, start);
        final previousStart = _previousStartForRange(_range, start);
        final periodExpenses = _expensesInPeriod(start, end);
        final previousExpenses = _expensesInPeriod(previousStart, start);
        final currentTotal = periodExpenses.totalAmount;
        final previousTotal = previousExpenses.totalAmount;
        final trend = _trendPoints(start, end);
        final categories = _categoryTotals(periodExpenses).take(4).toList();
        final comparison = _comparisonLabel(currentTotal, previousTotal);
        final increasedSpend = currentTotal > previousTotal;

        return AppPageContainer(
          children: [
            _SpendSummaryCard(
              total: currentTotal,
              comparison: comparison,
              increasedSpend: increasedSpend,
              loading: _loadingExpenses,
              range: _range,
              onRangeChanged: (range) => setState(() => _range = range),
              trend: trend,
            ),
            const SizedBox(height: 12),
            _CategoryBreakdownCard(categories: categories),
            const SizedBox(height: 20),
            const AppSectionHeader(title: 'History'),
            if (state.snapshot.activityItems.isEmpty)
              const SizedBox.shrink()
            else
              ...state.snapshot.activityItems.map(
                (item) => _ActivityTile(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _SpendSummaryCard extends StatelessWidget {
  const _SpendSummaryCard({
    required this.total,
    required this.comparison,
    required this.increasedSpend,
    required this.loading,
    required this.range,
    required this.onRangeChanged,
    required this.trend,
  });

  final double total;
  final String comparison;
  final bool increasedSpend;
  final bool loading;
  final _ActivityRange range;
  final ValueChanged<_ActivityRange> onRangeChanged;
  final List<AppChartPoint> trend;

  @override
  Widget build(BuildContext context) {
    final comparisonColor = increasedSpend
        ? Theme.of(context).colorScheme.error
        : AppMoney.positiveColor;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You spent',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppMoney.format(total),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      comparison,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: comparisonColor),
                    ),
                  ],
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                SegmentedButton<_ActivityRange>(
                  segments: _ActivityRange.values
                      .map(
                        (value) => ButtonSegment<_ActivityRange>(
                          value: value,
                          label: Text(_labelForRange(value)),
                        ),
                      )
                      .toList(growable: false),
                  selected: {range},
                  onSelectionChanged: (selection) {
                    onRangeChanged(selection.first);
                  },
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                      Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          AppLineChart(points: trend),
        ],
      ),
    );
  }

  static String _labelForRange(_ActivityRange value) {
    return switch (value) {
      _ActivityRange.week => 'Week',
      _ActivityRange.month => 'Month',
      _ActivityRange.year => 'Year',
    };
  }
}

class _CategoryBreakdownCard extends StatelessWidget {
  const _CategoryBreakdownCard({required this.categories});

  final List<_CategoryTotal> categories;

  @override
  Widget build(BuildContext context) {
    final total = categories.fold<double>(
      0,
      (sum, category) => sum + category.amount,
    );
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.primaryContainer,
      Theme.of(context).colorScheme.secondaryContainer,
      Theme.of(context).colorScheme.surfaceContainerHighest,
    ];
    final segments = categories
        .asMap()
        .entries
        .map((entry) {
          return AppChartSegment(
            label: entry.value.label,
            value: entry.value.amount,
            color: colors[entry.key % colors.length],
          );
        })
        .toList(growable: false);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('By category', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (categories.isEmpty)
            Text(
              'No spending yet',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            )
          else ...[
            AppSegmentedBar(segments: segments),
            const SizedBox(height: 14),
            ...categories.asMap().entries.map((entry) {
              final category = entry.value;
              final percent = total <= 0
                  ? 0
                  : (category.amount / total * 100).round();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors[entry.key % colors.length],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(category.label)),
                    Text(
                      '$percent%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 86,
                      child: Text(
                        AppMoney.format(category.amount),
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});

  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ListTile(
        leading: const AppAvatar(icon: Icons.receipt_long_outlined),
        title: Text(item.title),
        subtitle: Text(AppMoney.normalizeDisplayText(item.subtitle)),
        trailing: AppMoneyLabel(text: item.amountText, positive: item.positive),
      ),
    );
  }
}

class _CategoryTotal {
  const _CategoryTotal({
    required this.label,
    required this.amount,
    required this.count,
  });

  factory _CategoryTotal.empty(String label) {
    return _CategoryTotal(label: label, amount: 0, count: 0);
  }

  final String label;
  final double amount;
  final int count;

  _CategoryTotal add(double value) {
    return _CategoryTotal(
      label: label,
      amount: amount + value,
      count: count + 1,
    );
  }
}

extension on List<Expense> {
  double get totalAmount =>
      fold<double>(0, (sum, expense) => sum + expense.amount);
}
