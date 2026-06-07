import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/data/models/freshness_snapshot.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/data/repositories/freshness_repository.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/expenses/view/add_expense_page.dart';
import 'package:expense_tracker/features/activity/models/activity_feed.dart';
import 'package:expense_tracker/features/activity/repositories/activity_feed_repository.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:expense_tracker/features/groups/view/groups_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

class ActivityPage extends StatefulWidget {
  const ActivityPage({
    this.groupsRepository,
    this.groupsClient,
    this.freshnessRepository,
    this.activityFeedRepository,
    this.autoRefresh = false,
    super.key,
  });

  final ApiGroupsRepository? groupsRepository;
  final http.Client? groupsClient;
  final FreshnessRepository? freshnessRepository;
  final ActivityFeedRepository? activityFeedRepository;
  final bool autoRefresh;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

enum _ActivityRange { week, month, year }

class _ActivityPageState extends State<ActivityPage> {
  ExpenseRepository? _repository;
  http.Client? _ownedGroupsClient;
  late final ApiGroupsRepository _groupsRepository;
  late final FreshnessRepository _freshnessRepository;
  late final bool _ownsFreshnessRepository;
  late final ActivityFeedRepository _activityFeedRepository;
  late final bool _ownsActivityFeedRepository;
  List<Expense> _expenses = const [];
  List<_GroupExpenseEntry> _groupExpenses = const [];
  DateTime? _activityFreshnessCursor;
  _ActivityRange _range = _ActivityRange.week;
  bool _loadedRepository = false;
  bool _loadingExpenses = false;

  @override
  void initState() {
    super.initState();
    final client = widget.groupsClient ?? http.Client();
    if (widget.groupsRepository == null && widget.groupsClient == null) {
      _ownedGroupsClient = client;
    }
    _groupsRepository =
        widget.groupsRepository ?? ApiGroupsRepository(client: client);
    _freshnessRepository = widget.freshnessRepository ?? FreshnessRepository();
    _ownsFreshnessRepository = widget.freshnessRepository == null;
    _activityFeedRepository =
        widget.activityFeedRepository ?? ActivityFeedRepository();
    _ownsActivityFeedRepository = widget.activityFeedRepository == null;
  }

  @override
  void dispose() {
    _ownedGroupsClient?.close();
    if (_ownsFreshnessRepository) {
      _freshnessRepository.dispose();
    }
    if (_ownsActivityFeedRepository) {
      _activityFeedRepository.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedRepository) return;
    _loadedRepository = true;
    _repository = context.read<ExpenseRepository?>();
    _refreshActivityData();
  }

  Future<void> _refreshActivityData({bool showLoading = true}) async {
    setState(
      () => _loadingExpenses =
          showLoading || (_expenses.isEmpty && _groupExpenses.isEmpty),
    );
    final personalFuture = _loadPersonalExpenses();
    final groupFuture = _loadGroupExpenses();
    final personalExpenses = await personalFuture;
    final groupExpenses = await groupFuture;
    if (!mounted) return;
    setState(() {
      _expenses = personalExpenses;
      _groupExpenses = groupExpenses;
      _loadingExpenses = false;
    });
    await _refreshActivityCursor();
  }

  Future<void> _autoRefreshActivityData() async {
    final previousCursor = _activityFreshnessCursor;
    final freshness = await _freshnessRepository.fetchFreshness(
      since: previousCursor,
      sections: const ['activity'],
    );
    final activity = freshness.sections['activity'];
    if (activity != null) {
      await _applyActivityTombstones(activity);
      if (!activity.changed &&
          (_expenses.isNotEmpty || _groupExpenses.isNotEmpty)) {
        _activityFreshnessCursor = freshness.serverTime;
        return;
      }
      if (previousCursor != null &&
          await _mergeActivityFeed(since: previousCursor)) {
        return;
      }
    }
    await _refreshActivityData(showLoading: false);
    _activityFreshnessCursor = freshness.serverTime;
  }

  Future<void> _applyActivityTombstones(FreshnessSection activity) async {
    await _applyActivityDeletes(
      personalDeletedIds: activity.personalDeletedIds,
      groupDeleted: activity.groupDeleted,
      deletedGroupIds: activity.deletedGroupIds,
    );
  }

  Future<void> _applyActivityDeletes({
    Iterable<String> personalDeletedIds = const [],
    Iterable<GroupExpenseTombstone> groupDeleted = const [],
    Iterable<String> deletedGroupIds = const [],
  }) async {
    final personalDeleted = personalDeletedIds.toSet();
    final deletedGroupExpenses = groupDeleted.toList(growable: false);
    final deletedGroups = deletedGroupIds.toSet();
    if (personalDeleted.isEmpty &&
        deletedGroupExpenses.isEmpty &&
        deletedGroups.isEmpty) {
      return;
    }

    _repository?.removeCachedDeletedIds(personalDeleted);
    await _groupsRepository.removeCachedGroupIds(deletedGroups);
    final groupDeletedByGroup = <String, Set<String>>{};
    for (final tombstone in deletedGroupExpenses) {
      groupDeletedByGroup
          .putIfAbsent(tombstone.groupId, () => <String>{})
          .add(tombstone.expenseId);
    }
    for (final entry in groupDeletedByGroup.entries) {
      await _groupsRepository.removeCachedExpenseIds(entry.key, entry.value);
    }

    if (!mounted) return;
    setState(() {
      if (personalDeleted.isNotEmpty) {
        _expenses = _expenses
            .where((expense) => !personalDeleted.contains(expense.id))
            .toList(growable: false);
      }
      if (groupDeletedByGroup.isNotEmpty) {
        _groupExpenses = _groupExpenses
            .where((entry) {
              if (deletedGroups.contains(entry.group.id)) {
                return false;
              }
              final deletedIds = groupDeletedByGroup[entry.group.id];
              return deletedIds == null ||
                  !deletedIds.contains(entry.expense.id);
            })
            .toList(growable: false);
      } else if (deletedGroups.isNotEmpty) {
        _groupExpenses = _groupExpenses
            .where((entry) => !deletedGroups.contains(entry.group.id))
            .toList(growable: false);
      }
    });
  }

  Future<void> _refreshActivityCursor() async {
    try {
      final freshness = await _freshnessRepository.fetchFreshness(
        sections: const ['activity'],
      );
      _activityFreshnessCursor = freshness.serverTime;
    } catch (_) {}
  }

  Future<bool> _mergeActivityFeed({required DateTime since}) async {
    try {
      final feed = await _activityFeedRepository.fetchActivity(since: since);
      await _mergeActivityFeedPayload(feed);
      _activityFreshnessCursor = feed.serverTime;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _mergeActivityFeedPayload(ActivityFeed feed) async {
    await _applyActivityDeletes(
      personalDeletedIds: feed.tombstones.personalDeletedIds,
      groupDeleted: feed.tombstones.groupDeleted,
      deletedGroupIds: feed.tombstones.deletedGroupIds,
    );

    final personalUpdates = feed.entries
        .map((entry) => entry.personalExpense)
        .whereType<Expense>()
        .where((expense) => expense.id.isNotEmpty)
        .toList(growable: false);
    final groupUpdates = feed.entries
        .where(
          (entry) =>
              entry.group != null &&
              entry.groupExpense != null &&
              entry.group!.id.isNotEmpty &&
              entry.groupExpense!.id.isNotEmpty,
        )
        .map(
          (entry) => _GroupExpenseEntry(
            group: entry.group!,
            expense: entry.groupExpense!,
          ),
        )
        .toList(growable: false);

    _repository?.upsertCachedExpenses(personalUpdates);
    final groupUpdatesByGroup = <String, List<GroupExpense>>{};
    for (final entry in groupUpdates) {
      groupUpdatesByGroup
          .putIfAbsent(entry.group.id, () => <GroupExpense>[])
          .add(entry.expense);
    }
    for (final entry in groupUpdatesByGroup.entries) {
      await _groupsRepository.upsertCachedExpenses(entry.key, entry.value);
    }

    if (!mounted) return;
    setState(() {
      if (personalUpdates.isNotEmpty) {
        final byId = <String, Expense>{
          for (final expense in _expenses) expense.id: expense,
        };
        for (final expense in personalUpdates) {
          byId[expense.id] = expense;
        }
        _expenses = byId.values.toList(growable: false);
      }
      if (groupUpdates.isNotEmpty) {
        final byKey = <String, _GroupExpenseEntry>{
          for (final entry in _groupExpenses)
            '${entry.group.id}:${entry.expense.id}': entry,
        };
        for (final entry in groupUpdates) {
          byKey['${entry.group.id}:${entry.expense.id}'] = entry;
        }
        _groupExpenses = byKey.values.toList(growable: false);
      }
    });
  }

  Future<List<Expense>> _loadPersonalExpenses() async {
    final repository = _repository;
    if (repository == null) return const [];
    try {
      await repository.refresh();
      return repository.getExpenses();
    } catch (_) {
      return repository.getExpenses();
    }
  }

  Future<List<_GroupExpenseEntry>> _loadGroupExpenses() async {
    var groups = await _groupsRepository.getCachedGroups();
    var entries = await _groupExpenseEntriesFrom(groups, cached: true);
    try {
      groups = await _groupsRepository.fetchGroups();
      entries = await _groupExpenseEntriesFrom(groups, cached: false);
    } catch (_) {
      if (entries.isEmpty && groups.isEmpty) {
        groups = await _groupsRepository.getCachedGroups();
        entries = await _groupExpenseEntriesFrom(groups, cached: true);
      }
    }
    return entries;
  }

  Future<List<_GroupExpenseEntry>> _groupExpenseEntriesFrom(
    List<GroupSummary> groups, {
    required bool cached,
  }) async {
    final entries = <_GroupExpenseEntry>[];
    for (final group in groups) {
      final expenses = cached
          ? await _groupsRepository.getCachedExpenses(group.id)
          : await _groupsRepository.fetchExpenses(group.id);
      entries.addAll(
        expenses.map((expense) {
          return _GroupExpenseEntry(group: group, expense: expense);
        }),
      );
    }
    return entries;
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

  List<_ActivityExpenseEntry> _activityEntries() {
    final entries = [
      ..._expenses
          .where((expense) => !expense.deleted)
          .map(_ActivityExpenseEntry.personal),
      ..._groupExpenses.map(_ActivityExpenseEntry.group),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  List<_ActivityExpenseEntry> _entriesInPeriod(
    List<_ActivityExpenseEntry> entries,
    DateTime start,
    DateTime end,
  ) {
    return entries
        .where((entry) {
          final date = entry.date;
          return !date.isBefore(start) && date.isBefore(end);
        })
        .toList(growable: false);
  }

  List<AppChartPoint> _trendPoints(
    List<_ActivityExpenseEntry> entries,
    DateTime start,
    DateTime end,
    String currency,
  ) {
    switch (_range) {
      case _ActivityRange.week:
        return List.generate(7, (index) {
          final day = start.add(Duration(days: index));
          final next = day.add(const Duration(days: 1));
          return AppChartPoint(
            label: _weekdayLabel(day),
            value: _entriesInPeriod(
              entries,
              day,
              next,
            ).totalAmountForCurrency(currency),
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
              value: _entriesInPeriod(
                entries,
                cursor,
                next,
              ).totalAmountForCurrency(currency),
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
            value: _entriesInPeriod(
              entries,
              month,
              next,
            ).totalAmountForCurrency(currency),
          );
        });
    }
  }

  List<_CategoryTotal> _categoryTotals(List<_ActivityExpenseEntry> expenses) {
    final totals = <String, _CategoryTotal>{};
    for (final expense in expenses) {
      final label = expense.category.trim().isEmpty
          ? 'Other'
          : expense.category.trim();
      final current = totals[label] ?? _CategoryTotal.empty(label);
      totals[label] = current.add(expense);
    }
    final values = totals.values.toList(growable: false)
      ..sort((a, b) => b.sortAmount.compareTo(a.sortAmount));
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

  String _comparisonLabel(
    Map<String, double> current,
    Map<String, double> previous,
  ) {
    final range = _rangeLabel(_range).toLowerCase();
    final currencies = {...current.keys, ...previous.keys}
      ..removeWhere((currency) {
        final currentAmount = current[currency] ?? 0;
        final previousAmount = previous[currency] ?? 0;
        return currentAmount.abs() <= 0.005 && previousAmount.abs() <= 0.005;
      });
    if (currencies.isEmpty) {
      return 'No change vs last $range';
    }
    if (currencies.length > 1) {
      if (previous.isEmpty) {
        return 'No spend last $range';
      }
      return 'Last $range: ${AppMoney.formatCurrencyAmounts(previous)}';
    }
    final currency = currencies.first;
    final currentAmount = current[currency] ?? 0;
    final previousAmount = previous[currency] ?? 0;
    if (previousAmount <= 0 && currentAmount <= 0) {
      return 'No change vs last $range';
    }
    if (previousAmount <= 0) return '+100% vs last $range';
    final delta = ((currentAmount - previousAmount) / previousAmount) * 100;
    final sign = delta >= 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(0)}% vs last $range';
  }

  bool _hasIncreasedSpend(
    Map<String, double> current,
    Map<String, double> previous,
  ) {
    for (final currency in {...current.keys, ...previous.keys}) {
      if ((current[currency] ?? 0) > (previous[currency] ?? 0) + 0.005) {
        return true;
      }
    }
    return false;
  }

  String? _singleCurrencyForTrend(
    Map<String, double> current,
    Map<String, double> previous,
  ) {
    final currencies = {...current.keys, ...previous.keys}
      ..removeWhere((currency) {
        final currentAmount = current[currency] ?? 0;
        final previousAmount = previous[currency] ?? 0;
        return currentAmount.abs() <= 0.005 && previousAmount.abs() <= 0.005;
      });
    return currencies.length == 1 ? currencies.first : null;
  }

  Future<void> _editExpense(Expense expense) async {
    final bloc = context.read<ExpensesBloc?>();
    if (bloc == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BlocProvider.value(
          value: bloc,
          child: AddExpensePage(expense: expense),
        ),
      ),
    );
    if (changed == true && mounted) {
      await _refreshActivityData();
    }
  }

  Future<void> _editGroupExpense(_GroupExpenseEntry entry) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => GroupDetailsPage(
          group: entry.group,
          repository: _groupsRepository,
          initialExpenseId: entry.expense.id,
          autoRefresh: true,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _refreshActivityData();
    }
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
        final activityEntries = _activityEntries();
        final periodExpenses = _entriesInPeriod(activityEntries, start, end);
        final previousExpenses = _entriesInPeriod(
          activityEntries,
          previousStart,
          start,
        );
        final currentTotals = periodExpenses.totalAmountsByCurrency;
        final previousTotals = previousExpenses.totalAmountsByCurrency;
        final trendCurrency = _singleCurrencyForTrend(
          currentTotals,
          previousTotals,
        );
        final trend = trendCurrency == null
            ? const <AppChartPoint>[]
            : _trendPoints(activityEntries, start, end, trendCurrency);
        final categories = _categoryTotals(periodExpenses).take(4).toList();
        final comparison = _comparisonLabel(currentTotals, previousTotals);
        final increasedSpend = _hasIncreasedSpend(
          currentTotals,
          previousTotals,
        );

        return AppPageContainer(
          onRefresh: () => _refreshActivityData(showLoading: false),
          onAutoRefresh: _autoRefreshActivityData,
          autoRefresh: widget.autoRefresh,
          children: [
            _SpendSummaryCard(
              totalText: AppMoney.formatCurrencyAmounts(currentTotals),
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
            if (periodExpenses.isNotEmpty)
              ...periodExpenses.map(
                (entry) => _ExpenseActivityTile(
                  entry: entry,
                  onTap: () {
                    final personalExpense = entry.personalExpense;
                    final groupExpense = entry.groupExpense;
                    if (personalExpense != null) {
                      _editExpense(personalExpense);
                    } else if (groupExpense != null) {
                      _editGroupExpense(groupExpense);
                    }
                  },
                ),
              )
            else if (activityEntries.isNotEmpty) ...[
              const AppEmptyState(
                title: 'No activity in this period',
                subtitle: 'Older expenses are shown below for context.',
              ),
              const SizedBox(height: 12),
              const AppSectionHeader(title: 'Older history'),
              ...activityEntries.map(
                (entry) => _ExpenseActivityTile(
                  entry: entry,
                  onTap: () {
                    final personalExpense = entry.personalExpense;
                    final groupExpense = entry.groupExpense;
                    if (personalExpense != null) {
                      _editExpense(personalExpense);
                    } else if (groupExpense != null) {
                      _editGroupExpense(groupExpense);
                    }
                  },
                ),
              ),
            ] else if (state.snapshot.activityItems.isEmpty)
              const AppEmptyState(
                title: 'No activity yet',
                subtitle:
                    'Saved expenses and group updates for this period will appear here.',
              )
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

class _ExpenseActivityTile extends StatelessWidget {
  const _ExpenseActivityTile({required this.entry, required this.onTap});

  final _ActivityExpenseEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final category = entry.category.trim();
    final date = entry.date.toLocal().toString().split(' ').first;

    return AppCard(
      child: ListTile(
        onTap: onTap,
        leading: AppAvatar(icon: entry.icon),
        title: Text(entry.title),
        subtitle: Text(category.isEmpty ? date : '$category · $date'),
        trailing: AppMoneyLabel(
          text: AppMoney.formatCurrency(entry.amount, entry.currency),
          positive: false,
          neutral: true,
        ),
      ),
    );
  }
}

class _GroupExpenseEntry {
  const _GroupExpenseEntry({required this.group, required this.expense});

  final GroupSummary group;
  final GroupExpense expense;
}

class _ActivityExpenseEntry {
  const _ActivityExpenseEntry({
    required this.title,
    required this.category,
    required this.amount,
    required this.currency,
    required this.amountsByCurrency,
    required this.date,
    required this.icon,
    this.personalExpense,
    this.groupExpense,
  });

  factory _ActivityExpenseEntry.personal(Expense expense) {
    return _ActivityExpenseEntry(
      title: expense.title,
      category: (expense.category ?? '').trim(),
      amount: expense.amount,
      currency: expense.currency,
      amountsByCurrency: {expense.currency: expense.amount},
      date: expense.createdAt,
      icon: Icons.receipt_long_outlined,
      personalExpense: expense,
    );
  }

  factory _ActivityExpenseEntry.group(_GroupExpenseEntry entry) {
    final groupLabel = switch (entry.group.groupType) {
      GroupType.family => 'Family',
      GroupType.split => 'Group',
    };
    final description = entry.expense.description.trim();
    return _ActivityExpenseEntry(
      title: description.isEmpty ? entry.group.name : description,
      category: '$groupLabel · ${entry.group.name}',
      amount: entry.expense.amount,
      currency: entry.expense.currency,
      amountsByCurrency: entry.expense.amountsByCurrency,
      date: entry.expense.date,
      icon: entry.group.groupType == GroupType.family
          ? Icons.home_outlined
          : Icons.group_outlined,
      groupExpense: entry,
    );
  }

  final String title;
  final String category;
  final double amount;
  final String currency;
  final Map<String, double> amountsByCurrency;
  final DateTime date;
  final IconData icon;
  final Expense? personalExpense;
  final _GroupExpenseEntry? groupExpense;
}

class _SpendSummaryCard extends StatelessWidget {
  const _SpendSummaryCard({
    required this.totalText,
    required this.comparison,
    required this.increasedSpend,
    required this.loading,
    required this.range,
    required this.onRangeChanged,
    required this.trend,
  });

  final String totalText;
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
                      totalText,
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
          if (trend.isNotEmpty) AppLineChart(points: trend),
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
    final currencyCount = categories
        .expand((category) => category.amountsByCurrency.keys)
        .toSet()
        .length;
    final showShares = currencyCount <= 1;
    final total = categories.fold<double>(
      0,
      (sum, category) => sum + category.sortAmount,
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
            value: entry.value.sortAmount,
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
            if (showShares) ...[
              AppSegmentedBar(segments: segments),
              const SizedBox(height: 14),
            ],
            ...categories.asMap().entries.map((entry) {
              final category = entry.value;
              final percent = !showShares || total <= 0
                  ? 0
                  : (category.sortAmount / total * 100).round();
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
                    if (showShares) ...[
                      Text(
                        '$percent%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 12),
                    ],
                    SizedBox(
                      width: showShares ? 86 : 150,
                      child: Text(
                        AppMoney.formatCurrencyAmounts(
                          category.amountsByCurrency,
                        ),
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
    required this.amountsByCurrency,
    required this.count,
  });

  factory _CategoryTotal.empty(String label) {
    return _CategoryTotal(label: label, amountsByCurrency: const {}, count: 0);
  }

  final String label;
  final Map<String, double> amountsByCurrency;
  final int count;

  double get sortAmount =>
      amountsByCurrency.values.fold<double>(0, (sum, amount) => sum + amount);

  _CategoryTotal add(_ActivityExpenseEntry entry) {
    final nextAmounts = Map<String, double>.of(amountsByCurrency);
    for (final item in entry.amountsByCurrency.entries) {
      nextAmounts[item.key] = (nextAmounts[item.key] ?? 0) + item.value;
    }
    return _CategoryTotal(
      label: label,
      amountsByCurrency: nextAmounts,
      count: count + 1,
    );
  }
}

extension on List<_ActivityExpenseEntry> {
  Map<String, double> get totalAmountsByCurrency {
    final totals = <String, double>{};
    for (final expense in this) {
      for (final amount in expense.amountsByCurrency.entries) {
        totals[amount.key] = (totals[amount.key] ?? 0) + amount.value;
      }
    }
    totals.removeWhere((_, amount) => amount.abs() <= 0.005);
    return totals;
  }

  double totalAmountForCurrency(String currency) {
    return fold<double>(
      0,
      (sum, expense) => sum + (expense.amountsByCurrency[currency] ?? 0),
    );
  }
}
