import 'dart:async';

import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/data/repositories/freshness_repository.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:expense_tracker/features/planning/view/monthly_planning_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    this.onOpenFriends,
    this.onOpenGroups,
    this.onOpenFamily,
    this.onOpenRecurring,
    this.onOpenAction,
    this.onAddExpenseForCategory,
    this.onRecordPlannedPayment,
    this.onOpenActivityCategory,
    this.freshnessRepository,
    this.monthlyPlanRepository,
    this.autoRefresh = false,
    super.key,
  });

  final VoidCallback? onOpenFriends;
  final VoidCallback? onOpenGroups;
  final VoidCallback? onOpenFamily;
  final VoidCallback? onOpenRecurring;
  final void Function(DailyActionItem item)? onOpenAction;
  final ValueChanged<String>? onAddExpenseForCategory;
  final Future<bool> Function(
    String category, {
    required double amount,
    required String currency,
  })?
  onRecordPlannedPayment;
  final ValueChanged<String>? onOpenActivityCategory;
  final FreshnessRepository? freshnessRepository;
  final MonthlyPlanRepository? monthlyPlanRepository;
  final bool autoRefresh;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var _planRefreshToken = 0;
  late final FreshnessRepository _freshnessRepository;
  late final bool _ownsFreshnessRepository;
  DateTime? _dashboardFreshnessCursor;
  MonthlyPlan? _monthlyPlan;

  @override
  void initState() {
    super.initState();
    _freshnessRepository = widget.freshnessRepository ?? FreshnessRepository();
    _ownsFreshnessRepository = widget.freshnessRepository == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_markDashboardFreshnessSeen());
      }
    });
  }

  @override
  void dispose() {
    if (_ownsFreshnessRepository) {
      _freshnessRepository.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshDashboard(DashboardSnapshotCubit dashboardCubit) async {
    await dashboardCubit.load(showLoading: false);
    if (!mounted) return;
    setState(() => _planRefreshToken += 1);
    unawaited(_markDashboardFreshnessSeen());
  }

  Future<void> _autoRefreshDashboard(
    DashboardSnapshotCubit dashboardCubit,
  ) async {
    final freshness = await _freshnessRepository.fetchFreshness(
      since: _dashboardFreshnessCursor,
      sections: const ['dashboard', 'plans'],
    );
    final dashboard = freshness.sections['dashboard'];
    final plans = freshness.sections['plans'];
    final changed = (dashboard?.changed ?? true) || (plans?.changed ?? false);
    if (!changed && dashboardCubit.state is DashboardSnapshotLoaded) {
      _dashboardFreshnessCursor = freshness.serverTime;
      return;
    }

    await dashboardCubit.load(showLoading: false);
    if (!mounted) return;
    setState(() => _planRefreshToken += 1);
    _dashboardFreshnessCursor = freshness.serverTime;
  }

  Future<void> _markDashboardFreshnessSeen() async {
    try {
      final freshness = await _freshnessRepository.fetchFreshness(
        sections: const ['dashboard', 'plans'],
      );
      _dashboardFreshnessCursor = freshness.serverTime;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DashboardSnapshotCubit>().state;
    final dashboardCubit = context.read<DashboardSnapshotCubit>();

    if (state is DashboardSnapshotFailure) {
      return AppPageContainer(
        maxWidth: 1120,
        onRefresh: () => _refreshDashboard(dashboardCubit),
        onAutoRefresh: () => _autoRefreshDashboard(dashboardCubit),
        autoRefresh: widget.autoRefresh,
        children: [
          AppEmptyState(
            title: 'Dashboard unavailable',
            subtitle: state.message,
          ),
        ],
      );
    }
    if (state is! DashboardSnapshotLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final snapshot = state.snapshot;
    return AppPageContainer(
      maxWidth: 1120,
      padding: const EdgeInsets.all(16),
      onRefresh: () => _refreshDashboard(dashboardCubit),
      onAutoRefresh: () => _autoRefreshDashboard(dashboardCubit),
      autoRefresh: widget.autoRefresh,
      children: [
        _InsightStrip(snapshot: snapshot),
        const SizedBox(height: 16),
        const _PlanningAssistantCard(),
        const SizedBox(height: 16),
        _AdaptiveColumns(
          breakpoint: 900,
          spacing: 12,
          flexes: const [5, 4],
          children: [
            _BudgetOverviewCard(plan: _monthlyPlan, snapshot: snapshot),
            _NeedsAttentionSection(
              items: snapshot.actionItems,
              onOpenFriends: widget.onOpenFriends,
              onOpenGroups: widget.onOpenGroups,
              onOpenFamily: widget.onOpenFamily,
              onOpenRecurring: widget.onOpenRecurring,
              onOpenAction: widget.onOpenAction,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _AdaptiveColumns(
          breakpoint: 860,
          spacing: 12,
          children: [
            _CashflowPanel(plan: _monthlyPlan, snapshot: snapshot),
            _CategoryFocusPanel(plan: _monthlyPlan),
            _SavingsGoalsPanel(plan: _monthlyPlan),
          ],
        ),
        const SizedBox(height: 16),
        MonthlyPlanningCard(
          title: 'Monthly budget',
          repository: widget.monthlyPlanRepository,
          refreshToken: _planRefreshToken,
          onAddExpenseForCategory: widget.onAddExpenseForCategory,
          onRecordPlannedPayment: widget.onRecordPlannedPayment,
          onReviewCategory: widget.onOpenActivityCategory,
          onPlanLoaded: _handlePlanLoaded,
        ),
        const SizedBox(height: 16),
        _AdaptiveColumns(
          breakpoint: 760,
          spacing: 12,
          children: [
            _SharedBalancesPanel(
              friendItems: snapshot.friendItems,
              groupItems: snapshot.groupItems,
              onOpenFriends: widget.onOpenFriends,
              onOpenGroups: widget.onOpenGroups,
            ),
            _SpendTrendPanel(items: snapshot.activityItems),
            _RecentActivityPanel(items: snapshot.activityItems),
          ],
        ),
      ],
    );
  }

  void _handlePlanLoaded(MonthlyPlan plan) {
    if (!mounted || identical(plan, _monthlyPlan)) return;
    setState(() => _monthlyPlan = plan);
  }
}

class _PlanningAssistantCard extends StatelessWidget {
  const _PlanningAssistantCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const prompts = [
      'Plan a trip',
      'Afford a big purchase',
      'Save by December',
      'Cut monthly spend',
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppMoney.positiveColor.withValues(alpha: 0.07),
            colors.surface,
          ],
          stops: const [0, 0.38],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppMoney.positiveColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const SizedBox.square(
                      dimension: 32,
                      child: Icon(
                        Icons.auto_awesome_outlined,
                        size: 17,
                        color: AppMoney.positiveColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Plan with AI',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Ask about trips, purchases, goals, or spending cuts.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Ask anything about this month...',
                  filled: true,
                  fillColor: colors.surfaceContainerHighest.withValues(
                    alpha: 0.38,
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Ask AI',
                    onPressed: () {},
                    icon: const Icon(Icons.auto_awesome),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: prompts
                    .map(
                      (prompt) => ActionChip(
                        label: Text(prompt),
                        onPressed: () {},
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightStrip extends StatelessWidget {
  const _InsightStrip({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final actionCount = snapshot.actionItems.length;
    final firstAction = snapshot.actionItems.isEmpty
        ? null
        : snapshot.actionItems.first;
    final balanceText = AppMoney.normalizeDisplayText(
      snapshot.overallAmountText,
    );
    final balanceMessage = snapshot.overallPositive
        ? '${snapshot.overallLabel}. $balanceText is in your favor right now.'
        : '${snapshot.overallLabel}. $balanceText needs settling.';
    final attentionMessage = firstAction == null
        ? 'No follow-ups are waiting. Your receipts, recurring reminders, and shared balances are quiet.'
        : '$actionCount ${actionCount == 1 ? 'item needs' : 'items need'} attention. Start with ${firstAction.title}.';

    return _AdaptiveColumns(
      breakpoint: 720,
      spacing: 12,
      children: [
        _InsightBanner(
          icon: Icons.auto_awesome_outlined,
          label: 'Summary',
          message: balanceMessage,
          tone: _InsightTone.positive,
        ),
        _InsightBanner(
          icon: firstAction == null
              ? Icons.task_alt_outlined
              : _attentionIcon(firstAction),
          label: firstAction == null ? 'Clear' : 'Needs attention',
          message: attentionMessage,
          tone: firstAction == null
              ? _InsightTone.neutral
              : _toneFor(firstAction),
        ),
      ],
    );
  }
}

enum _InsightTone { positive, warning, critical, neutral }

class _InsightBanner extends StatelessWidget {
  const _InsightBanner({
    required this.icon,
    required this.label,
    required this.message,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String message;
  final _InsightTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final resolved = switch (tone) {
      _InsightTone.positive => (
        background: const Color(0xFFE6F4EE),
        border: const Color(0xFFC3E6D9),
        foreground: AppMoney.positiveColor,
      ),
      _InsightTone.warning => (
        background: const Color(0xFFFFF8E6),
        border: const Color(0xFFF5DFA0),
        foreground: const Color(0xFF8A5E00),
      ),
      _InsightTone.critical => (
        background: colors.errorContainer.withValues(alpha: 0.64),
        border: colors.error.withValues(alpha: 0.24),
        foreground: colors.error,
      ),
      _InsightTone.neutral => (
        background: colors.surfaceContainerHighest.withValues(alpha: 0.52),
        border: colors.outlineVariant,
        foreground: colors.onSurfaceVariant,
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: resolved.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: resolved.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: resolved.foreground),
                const SizedBox(width: 6),
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: resolved.foreground,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: resolved.foreground,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeedsAttentionSection extends StatelessWidget {
  const _NeedsAttentionSection({
    required this.items,
    this.onOpenFriends,
    this.onOpenGroups,
    this.onOpenFamily,
    this.onOpenRecurring,
    this.onOpenAction,
  });

  final List<DailyActionItem> items;
  final VoidCallback? onOpenFriends;
  final VoidCallback? onOpenGroups;
  final VoidCallback? onOpenFamily;
  final VoidCallback? onOpenRecurring;
  final void Function(DailyActionItem item)? onOpenAction;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(5).toList(growable: false);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Needs attention',
            badge: items.isEmpty ? null : '${items.length} items',
          ),
          const SizedBox(height: 10),
          if (visibleItems.isEmpty)
            const _NoAttentionCard()
          else
            Column(
              children: [
                for (var index = 0; index < visibleItems.length; index++) ...[
                  _AttentionCard(
                    item: visibleItems[index],
                    onTap: _tapFor(visibleItems[index]),
                  ),
                  if (index < visibleItems.length - 1)
                    const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }

  VoidCallback? _tapFor(DailyActionItem item) {
    if (onOpenAction != null) {
      return () => onOpenAction!(item);
    }
    return switch (item.destination) {
      'friends' => onOpenFriends,
      'groups' => onOpenGroups,
      'family' => onOpenFamily,
      'recurring' => onOpenRecurring,
      _ => null,
    };
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.item, this.onTap});

  final DailyActionItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tone = _toneFor(item);
    final foreground = _foregroundFor(context, tone);
    final background = _backgroundFor(context, tone);
    final subtitle = item.subtitle.trim();

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SizedBox.square(
                  dimension: 36,
                  child: Icon(
                    _attentionIcon(item),
                    color: foreground,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusPill(
                          label: _badgeLabel(item),
                          color: foreground,
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        AppMoney.normalizeDisplayText(subtitle),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: onTap,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: Text(_primaryActionLabel(item)),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetOverviewCard extends StatelessWidget {
  const _BudgetOverviewCard({required this.plan, required this.snapshot});

  final MonthlyPlan? plan;
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loadedPlan = plan;
    final progress = loadedPlan == null || loadedPlan.totalBudget <= 0
        ? 0.0
        : (loadedPlan.totalActual / loadedPlan.totalBudget).clamp(0.0, 1.0);
    final monthLabel = _monthLabel(loadedPlan?.month);
    final remaining = loadedPlan?.totalRemaining ?? 0;
    final remainingPositive = remaining >= -0.005;
    final heroValue = loadedPlan == null
        ? AppMoney.normalizeDisplayText(snapshot.overallAmountText)
        : AppMoney.formatCurrency(remaining.abs(), loadedPlan.currency);
    final heroLabel = loadedPlan == null
        ? snapshot.overallLabel
        : remainingPositive
        ? 'left in $monthLabel'
        : 'over plan in $monthLabel';

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'Overview', actionLabel: monthLabel),
          const SizedBox(height: 8),
          Text(
            heroValue,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: loadedPlan == null
                  ? AppMoney.statusColor(
                      context,
                      positive: snapshot.overallPositive,
                    )
                  : AppMoney.statusColor(context, positive: remainingPositive),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            heroLabel,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (loadedPlan == null)
            _MetricStrip(
              metrics: [
                _MetricData(
                  label: 'Balance',
                  value: AppMoney.normalizeDisplayText(
                    snapshot.overallAmountText,
                  ),
                ),
                _MetricData(
                  label: 'Follow-ups',
                  value: snapshot.actionItems.length.toString(),
                ),
                _MetricData(
                  label: 'Shared',
                  value:
                      '${snapshot.friendItems.length + snapshot.groupItems.length}',
                ),
              ],
            )
          else ...[
            _ProgressLabel(
              leading: AppMoney.formatCurrency(
                loadedPlan.totalActual,
                loadedPlan.currency,
              ),
              trailing:
                  'of ${AppMoney.formatCurrency(loadedPlan.totalBudget, loadedPlan.currency)}',
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 14),
            _MetricStrip(
              metrics: [
                _MetricData(
                  label: 'Planned',
                  value: AppMoney.formatCurrency(
                    loadedPlan.totalBudget,
                    loadedPlan.currency,
                  ),
                ),
                _MetricData(
                  label: 'Spent',
                  value: AppMoney.formatCurrency(
                    loadedPlan.totalActual,
                    loadedPlan.currency,
                  ),
                ),
                _MetricData(
                  label: 'Remaining',
                  value: AppMoney.formatCurrency(
                    loadedPlan.totalRemaining.abs(),
                    loadedPlan.currency,
                  ),
                  positive: remainingPositive,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryFocusPanel extends StatelessWidget {
  const _CategoryFocusPanel({required this.plan});

  final MonthlyPlan? plan;

  @override
  Widget build(BuildContext context) {
    final loadedPlan = plan;
    final categories =
        (loadedPlan == null
              ? <MonthlyPlanCategory>[]
              : [...loadedPlan.categories])
          ..sort((a, b) {
            final byRisk = b.progress.compareTo(a.progress);
            if (byRisk != 0) return byRisk;
            return b.budget.compareTo(a.budget);
          });

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Budget focus'),
          const SizedBox(height: 8),
          if (loadedPlan == null || categories.isEmpty)
            Text(
              'Set a monthly plan to see category pressure here.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (var index = 0; index < categories.take(4).length; index++) ...[
              _CategoryFocusRow(
                category: categories[index],
                currency: loadedPlan.currency,
              ),
              if (index < categories.take(4).length - 1)
                const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _CashflowPanel extends StatelessWidget {
  const _CashflowPanel({required this.plan, required this.snapshot});

  final MonthlyPlan? plan;
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final loadedPlan = plan;
    final rows = loadedPlan == null
        ? [
            _CashflowRowData(
              label: 'Shared balance',
              amountText: AppMoney.normalizeDisplayText(
                snapshot.overallAmountText,
              ),
              fraction: snapshot.overallPositive ? 0.62 : 0.38,
              color: snapshot.overallPositive
                  ? AppMoney.positiveColor
                  : Theme.of(context).colorScheme.error,
            ),
            _CashflowRowData(
              label: 'Follow-ups',
              amountText: '${snapshot.actionItems.length} items',
              fraction: (snapshot.actionItems.length / 5).clamp(0.12, 1.0),
              color: const Color(0xFFE8A317),
            ),
          ]
        : _cashflowRowsFor(context, loadedPlan);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Cashflow',
            actionLabel: _monthLabel(plan?.month),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < rows.length; index++) ...[
            _CashflowBar(row: rows[index]),
            if (index < rows.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  List<_CashflowRowData> _cashflowRowsFor(
    BuildContext context,
    MonthlyPlan plan,
  ) {
    final colors = Theme.of(context).colorScheme;
    final maxAmount = [
      plan.totalBudget.abs(),
      plan.totalActual.abs(),
      _loanAmount(plan).abs(),
      plan.totalRemaining.abs(),
    ].fold<double>(1, (max, amount) => amount > max ? amount : max);
    double fraction(double value) => (value.abs() / maxAmount).clamp(0.08, 1.0);
    return [
      _CashflowRowData(
        label: 'Planned costs',
        amountText: AppMoney.formatCurrency(plan.totalBudget, plan.currency),
        fraction: fraction(plan.totalBudget),
        color: AppMoney.positiveColor,
      ),
      _CashflowRowData(
        label: 'Spent',
        amountText: AppMoney.formatCurrency(plan.totalActual, plan.currency),
        fraction: fraction(plan.totalActual),
        color: colors.primary,
      ),
      _CashflowRowData(
        label: 'Loan EMIs',
        amountText: AppMoney.formatCurrency(_loanAmount(plan), plan.currency),
        fraction: fraction(_loanAmount(plan)),
        color: const Color(0xFF7AA2F7),
      ),
      _CashflowRowData(
        label: plan.totalRemaining >= 0 ? 'Remaining' : 'Over plan',
        amountText: AppMoney.formatCurrency(
          plan.totalRemaining.abs(),
          plan.currency,
        ),
        fraction: fraction(plan.totalRemaining),
        color: plan.totalRemaining >= 0 ? AppMoney.positiveColor : colors.error,
      ),
    ];
  }
}

class _SavingsGoalsPanel extends StatelessWidget {
  const _SavingsGoalsPanel({required this.plan});

  final MonthlyPlan? plan;

  @override
  Widget build(BuildContext context) {
    final savings = plan == null
        ? const <MonthlyPlanCategory>[]
        : plan!.categories
              .where((category) => _isSavingsCategory(category.category))
              .toList(growable: false);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Savings goals'),
          const SizedBox(height: 8),
          if (plan == null || savings.isEmpty)
            Text(
              'No savings allocation in this plan yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (var index = 0; index < savings.take(3).length; index++) ...[
              _SavingsGoalRow(
                category: savings[index],
                currency: plan!.currency,
              ),
              if (index < savings.take(3).length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _SavingsGoalRow extends StatelessWidget {
  const _SavingsGoalRow({required this.category, required this.currency});

  final MonthlyPlanCategory category;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final progress = category.budget <= 0
        ? 0.0
        : category.actual / category.budget;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                AppMoney.formatCurrency(category.budget, currency),
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            color: AppMoney.positiveColor,
          ),
        ],
      ),
    );
  }
}

class _SpendTrendPanel extends StatelessWidget {
  const _SpendTrendPanel({required this.items});

  final List<ActivityItem> items;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(5).toList(growable: false);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Spend trend'),
          const SizedBox(height: 8),
          if (visibleItems.isEmpty)
            Text(
              'Recent expenses will appear here as the month builds.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (var index = 0; index < visibleItems.length; index++) ...[
              _TrendRow(item: visibleItems[index], index: index),
              if (index < visibleItems.length - 1) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.item, required this.index});

  final ActivityItem item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = item.positive ? AppMoney.positiveColor : colors.primary;
    return Row(
      children: [
        SizedBox(
          width: 86,
          child: Text(
            item.subtitle.isEmpty ? item.title : item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (1 - index * 0.13).clamp(0.2, 1.0),
              minHeight: 22,
              color: color,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          AppMoney.normalizeDisplayText(item.amountText),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppMoney.statusColor(context, positive: item.positive),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _CashflowBar extends StatelessWidget {
  const _CashflowBar({required this.row});

  final _CashflowRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            row.label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 22,
              value: row.fraction,
              color: row.color,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 76,
          child: Text(
            row.amountText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _CashflowRowData {
  const _CashflowRowData({
    required this.label,
    required this.amountText,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String amountText;
  final double fraction;
  final Color color;
}

class _CategoryFocusRow extends StatelessWidget {
  const _CategoryFocusRow({required this.category, required this.currency});

  final MonthlyPlanCategory category;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final overBudget = category.overBudget || category.remaining < -0.005;
    final progress = category.budget <= 0
        ? 0.0
        : category.progress.clamp(0.0, 1.0);
    final color = overBudget
        ? colors.error
        : progress >= 0.8
        ? const Color(0xFFC47B00)
        : AppMoney.positiveColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const SizedBox.square(dimension: 10),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                AppMoney.formatCurrency(category.actual, currency),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress, color: color),
        ],
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.metrics});

  final List<_MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < metrics.length; index++) ...[
          Expanded(child: _MetricBox(data: metrics[index])),
          if (index < metrics.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          children: [
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              data.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: data.positive == null
                    ? colors.onSurface
                    : AppMoney.statusColor(context, positive: data.positive!),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressLabel extends StatelessWidget {
  const _ProgressLabel({required this.leading, required this.trailing});

  final String leading;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          leading,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const Spacer(),
        Text(
          trailing,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _MetricData {
  const _MetricData({required this.label, required this.value, this.positive});

  final String label;
  final String value;
  final bool? positive;
}

class _NoAttentionCard extends StatelessWidget {
  const _NoAttentionCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.task_alt_outlined, color: AppMoney.positiveColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No follow-ups today',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedBalancesPanel extends StatelessWidget {
  const _SharedBalancesPanel({
    required this.friendItems,
    required this.groupItems,
    this.onOpenFriends,
    this.onOpenGroups,
  });

  final List<BalanceItem> friendItems;
  final List<BalanceItem> groupItems;
  final VoidCallback? onOpenFriends;
  final VoidCallback? onOpenGroups;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final item in friendItems.take(2))
        _BalanceEntry(item: item, type: 'Friend', onTap: onOpenFriends),
      for (final item in groupItems.take(2))
        _BalanceEntry(item: item, type: 'Group', onTap: onOpenGroups),
    ];

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Shared balances',
            actionLabel: entries.isEmpty ? null : 'See all',
            onAction: onOpenFriends ?? onOpenGroups,
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Text(
              'All settled',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            )
          else
            for (var index = 0; index < entries.length; index++) ...[
              _BalanceRow(entry: entries[index]),
              if (index < entries.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.entry});

  final _BalanceEntry entry;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final colors = Theme.of(context).colorScheme;
    final amountText = AppMoney.normalizeDisplayText(item.amountText);
    final amountColor = AppMoney.statusColor(
      context,
      positive: item.positive,
      neutral: amountText.toLowerCase().contains('settled'),
    );

    return InkWell(
      onTap: entry.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            AppAvatar(
              label: item.title,
              size: 36,
              backgroundColor: item.positive
                  ? const Color(0xFFE6F4EE)
                  : colors.surfaceContainerHighest,
              foregroundColor: amountColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    item.subtitle.isEmpty ? entry.type : item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              amountText,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: amountColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentActivityPanel extends StatelessWidget {
  const _RecentActivityPanel({required this.items});

  final List<ActivityItem> items;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Recent activity'),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              'No activity yet',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            )
          else
            for (var index = 0; index < items.take(5).length; index++) ...[
              _ActivityRow(item: items[index]),
              if (index < items.take(5).length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final amountText = AppMoney.normalizeDisplayText(item.amountText);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          AppAvatar(
            icon: item.positive
                ? Icons.arrow_downward_outlined
                : Icons.receipt_long_outlined,
            size: 36,
            backgroundColor: item.positive
                ? const Color(0xFFE6F4EE)
                : colors.errorContainer.withValues(alpha: 0.62),
            foregroundColor: item.positive
                ? AppMoney.positiveColor
                : colors.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            amountText,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppMoney.statusColor(context, positive: item.positive),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdaptiveColumns extends StatelessWidget {
  const _AdaptiveColumns({
    required this.children,
    required this.breakpoint,
    required this.spacing,
    this.flexes,
  });

  final List<Widget> children;
  final double breakpoint;
  final double spacing;
  final List<int>? flexes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index < children.length - 1) SizedBox(height: spacing),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(
                flex: flexes == null || index >= flexes!.length
                    ? 1
                    : flexes![index],
                child: children[index],
              ),
              if (index < children.length - 1) SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }
}

String _monthLabel(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    final now = DateTime.now();
    return _formatMonth(now.year, now.month);
  }
  final parts = raw.split('-');
  if (parts.length < 2) {
    return raw;
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) {
    return raw;
  }
  return _formatMonth(year, month);
}

String _formatMonth(int year, int month) {
  const monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${monthNames[month - 1]} $year';
}

bool _isSavingsCategory(String category) {
  final normalized = category.trim().toLowerCase();
  return normalized.contains('saving') ||
      normalized.contains('investment') ||
      normalized.contains('sip') ||
      normalized.contains('fixed deposit');
}

double _loanAmount(MonthlyPlan plan) {
  return plan.categories.fold<double>(0, (sum, category) {
    if (!_isLoanLikeCategory(category.category)) return sum;
    return sum + category.budget;
  });
}

bool _isLoanLikeCategory(String category) {
  final normalized = category.trim().toLowerCase();
  return normalized.contains('loan') || normalized.contains('emi');
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.badge,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? badge;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (badge != null)
          _StatusPill(label: badge!, color: colors.error)
        else if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _BalanceEntry {
  const _BalanceEntry({
    required this.item,
    required this.type,
    required this.onTap,
  });

  final BalanceItem item;
  final String type;
  final VoidCallback? onTap;
}

_InsightTone _toneFor(DailyActionItem item) {
  return switch (item.severity) {
    'critical' => _InsightTone.critical,
    'warning' => _InsightTone.warning,
    _ => _InsightTone.positive,
  };
}

Color _foregroundFor(BuildContext context, _InsightTone tone) {
  final colors = Theme.of(context).colorScheme;
  return switch (tone) {
    _InsightTone.positive => AppMoney.positiveColor,
    _InsightTone.warning => const Color(0xFFC47B00),
    _InsightTone.critical => colors.error,
    _InsightTone.neutral => colors.onSurfaceVariant,
  };
}

Color _backgroundFor(BuildContext context, _InsightTone tone) {
  final colors = Theme.of(context).colorScheme;
  return switch (tone) {
    _InsightTone.positive => const Color(0xFFE6F4EE),
    _InsightTone.warning => const Color(0xFFFFF4E0),
    _InsightTone.critical => colors.errorContainer.withValues(alpha: 0.64),
    _InsightTone.neutral => colors.surfaceContainerHighest,
  };
}

IconData _attentionIcon(DailyActionItem item) {
  if (item.actionType.contains('receipt')) {
    return Icons.receipt_long_outlined;
  }
  if (item.actionType.contains('budget')) {
    return Icons.trending_up_outlined;
  }
  if (item.destination == 'friends' || item.destination == 'family') {
    return Icons.people_outline;
  }
  if (item.destination == 'recurring') {
    return Icons.event_repeat_outlined;
  }
  return switch (item.severity) {
    'critical' => Icons.error_outline,
    'warning' => Icons.schedule_outlined,
    _ => Icons.task_alt_outlined,
  };
}

String _badgeLabel(DailyActionItem item) {
  return switch (item.severity) {
    'critical' => 'Urgent',
    'warning' => 'Due',
    _ => 'New',
  };
}

String _primaryActionLabel(DailyActionItem item) {
  final action = item.actionType.toLowerCase();
  if (action.contains('confirm')) return 'Confirm';
  if (action.contains('review')) return 'Review';
  if (action.contains('settle')) return 'Settle';
  return 'Open';
}
