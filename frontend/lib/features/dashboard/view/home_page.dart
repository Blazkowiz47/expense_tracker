import 'dart:math' as math;
import 'dart:async';

import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/data/repositories/freshness_repository.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _hybridAccent = Color(0xFF26A17B);
const _hybridAccentStrong = Color(0xFF1A8F6C);
const _hybridAccentSoft = Color(0xFFE6F4EE);
const _hybridNegative = Color(0xFFBA1A1A);
const _hybridNegativeSoft = Color(0xFFFDE7E7);
const _hybridNeutralSoft = Color(0xFFF0F2F4);
const _hybridTrack = Color(0xFFEEF0F3);
const _hybridWarning = Color(0xFFC47B00);
const _hybridWarningText = Color(0xFF8A5E00);
const _hybridWarningSoft = Color(0xFFFFF4E0);
const _hybridExpense = Color(0xFFE8A317);

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
  late final FreshnessRepository _freshnessRepository;
  late final bool _ownsFreshnessRepository;
  late final MonthlyPlanRepository _monthlyPlanRepository;
  late final bool _ownsMonthlyPlanRepository;
  DateTime? _dashboardFreshnessCursor;
  MonthlyPlan? _monthlyPlan;

  @override
  void initState() {
    super.initState();
    _freshnessRepository = widget.freshnessRepository ?? FreshnessRepository();
    _ownsFreshnessRepository = widget.freshnessRepository == null;
    _monthlyPlanRepository =
        widget.monthlyPlanRepository ?? MonthlyPlanRepository();
    _ownsMonthlyPlanRepository = widget.monthlyPlanRepository == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_markDashboardFreshnessSeen());
        unawaited(_loadMonthlyPlan());
      }
    });
  }

  @override
  void dispose() {
    if (_ownsFreshnessRepository) {
      _freshnessRepository.dispose();
    }
    if (_ownsMonthlyPlanRepository) {
      _monthlyPlanRepository.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshDashboard(DashboardSnapshotCubit dashboardCubit) async {
    await dashboardCubit.load(showLoading: false);
    if (!mounted) return;
    await _loadMonthlyPlan();
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
    if (plans?.changed ?? false) {
      await _loadMonthlyPlan();
    }
    _dashboardFreshnessCursor = freshness.serverTime;
  }

  Future<void> _loadMonthlyPlan() async {
    try {
      final plan = await _monthlyPlanRepository.fetchPlan(month: _currentMonth);
      if (!mounted) return;
      _handlePlanLoaded(plan);
    } catch (_) {}
  }

  String get _currentMonth {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
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
    final compact = MediaQuery.sizeOf(context).width < 700;
    final children = compact
        ? <Widget>[
            _InsightStrip(snapshot: snapshot),
            const SizedBox(height: 10),
            _MobileBudgetSummary(plan: _monthlyPlan, snapshot: snapshot),
            const SizedBox(height: 10),
            _NeedsAttentionSection(
              items: snapshot.actionItems,
              onOpenFriends: widget.onOpenFriends,
              onOpenGroups: widget.onOpenGroups,
              onOpenFamily: widget.onOpenFamily,
              onOpenRecurring: widget.onOpenRecurring,
              onOpenAction: widget.onOpenAction,
            ),
            const SizedBox(height: 10),
            const _PlanningAssistantCard(),
            const SizedBox(height: 10),
            _CategoryBreakdownPanel(plan: _monthlyPlan),
            const SizedBox(height: 10),
            _SpendTrendChartPanel(items: snapshot.activityItems),
            const SizedBox(height: 10),
            _SavingsGoalsPanel(plan: _monthlyPlan),
            const SizedBox(height: 10),
            _SharedBalancesPanel(
              friendItems: snapshot.friendItems,
              groupItems: snapshot.groupItems,
              onOpenFriends: widget.onOpenFriends,
              onOpenGroups: widget.onOpenGroups,
            ),
            const SizedBox(height: 10),
            _RecentActivityPanel(items: snapshot.activityItems),
          ]
        : <Widget>[
            _InsightStrip(snapshot: snapshot),
            const SizedBox(height: 16),
            const _PlanningAssistantCard(),
            const SizedBox(height: 16),
            _NeedsAttentionSection(
              items: snapshot.actionItems,
              onOpenFriends: widget.onOpenFriends,
              onOpenGroups: widget.onOpenGroups,
              onOpenFamily: widget.onOpenFamily,
              onOpenRecurring: widget.onOpenRecurring,
              onOpenAction: widget.onOpenAction,
            ),
            const SizedBox(height: 16),
            _AdaptiveColumns(
              breakpoint: 820,
              spacing: 16,
              flexes: const [5, 5],
              children: [
                _MonthlyBudgetChartCard(plan: _monthlyPlan, snapshot: snapshot),
                _CashflowPanel(plan: _monthlyPlan, snapshot: snapshot),
              ],
            ),
            const SizedBox(height: 16),
            _AdaptiveColumns(
              breakpoint: 840,
              spacing: 16,
              flexes: const [7, 4],
              children: [
                _CategoryBreakdownPanel(plan: _monthlyPlan),
                _SpendTrendChartPanel(items: snapshot.activityItems),
              ],
            ),
            const SizedBox(height: 16),
            _AdaptiveColumns(
              breakpoint: 760,
              spacing: 16,
              children: [
                _SharedBalancesPanel(
                  friendItems: snapshot.friendItems,
                  groupItems: snapshot.groupItems,
                  onOpenFriends: widget.onOpenFriends,
                  onOpenGroups: widget.onOpenGroups,
                ),
                _SavingsGoalsPanel(plan: _monthlyPlan),
                _RecentActivityPanel(items: snapshot.activityItems),
              ],
            ),
          ];

    return AppPageContainer(
      maxWidth: compact ? double.infinity : 1040,
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 20,
        compact ? 16 : 20,
        compact ? 16 : 20,
        24,
      ),
      onRefresh: () => _refreshDashboard(dashboardCubit),
      onAutoRefresh: () => _autoRefreshDashboard(dashboardCubit),
      autoRefresh: widget.autoRefresh,
      children: children,
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
      'Plan a trip to Lofoten',
      'Can I afford a NOK 30,000 laptop?',
      'Save NOK 50,000 by December',
      'Cut my monthly spending',
    ];
    return _HybridCard(
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _hybridAccentSoft,
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Ask about trips, purchases, goals, or spending cuts.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    readOnly: true,
                    cursorColor: _hybridAccentStrong,
                    decoration: InputDecoration(
                      hintText:
                          'Ask anything - plan a trip, afford a big purchase, save for a goal...',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFF45474A)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Ask AI'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _hybridAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(100, 48),
                  ),
                ),
              ],
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
                      backgroundColor: const Color(0xFFF7F8F9),
                      side: const BorderSide(color: Color(0xFFE2E4E8)),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: const Border(
                  left: BorderSide(color: AppMoney.positiveColor, width: 3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '"Save NOK 50,000 by December"',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'AI PLAN',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppMoney.positiveColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const _AiPlanLine(
                      index: 1,
                      text:
                          'Set aside NOK 8,334/month - well within your current surplus.',
                    ),
                    const _AiPlanLine(
                      index: 2,
                      text:
                          'Reduce discretionary spend by NOK 2,000/month to accelerate the goal.',
                    ),
                    const _AiPlanLine(
                      index: 3,
                      text:
                          'After loan EMIs clear, redirect that amount toward savings.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiPlanLine extends StatelessWidget {
  const _AiPlanLine({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: _hybridAccentSoft,
            child: Text(
              '$index',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppMoney.positiveColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
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
    final resolved = switch (tone) {
      _InsightTone.positive => (
        background: _hybridAccentSoft,
        border: const Color(0xFFC3E6D9),
        foreground: AppMoney.positiveColor,
      ),
      _InsightTone.warning => (
        background: const Color(0xFFFFF8E6),
        border: const Color(0xFFF5DFA0),
        foreground: _hybridWarningText,
      ),
      _InsightTone.critical => (
        background: _hybridNegativeSoft,
        border: const Color(0xFFF6C6C6),
        foreground: _hybridNegative,
      ),
      _InsightTone.neutral => (
        background: Colors.white,
        border: const Color(0xFFE2E4E8),
        foreground: const Color(0xFF58646F),
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
    return Column(
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
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 720;
              final itemWidth = twoColumns
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in visibleItems)
                    SizedBox(
                      width: itemWidth,
                      child: _AttentionCard(item: item, onTap: _tapFor(item)),
                    ),
                ],
              );
            },
          ),
      ],
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
      color: colors.surface,
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
                        backgroundColor: _hybridAccent,
                        foregroundColor: Colors.white,
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

class _HybridCard extends StatelessWidget {
  const _HybridCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0A000000),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _MobileBudgetSummary extends StatelessWidget {
  const _MobileBudgetSummary({required this.plan, required this.snapshot});

  final MonthlyPlan? plan;
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final loadedPlan = plan;
    final currency = loadedPlan?.currency ?? 'NOK';
    final total = loadedPlan?.totalBudget ?? 12294;
    final spent = loadedPlan?.totalActual ?? 0;
    final remaining = loadedPlan?.totalRemaining ?? total;
    final progress = total <= 0 ? 0.0 : (spent / total).clamp(0.0, 1.0);
    final categories = _plannedCategories(loadedPlan);
    final primary = categories.isEmpty
        ? const [
            _CategorySlice(
              label: 'Loan EMIs due',
              amount: 4294,
              color: Color(0xFFE11D1D),
            ),
            _CategorySlice(
              label: 'Housing',
              amount: 8000,
              color: Color(0xFF111827),
            ),
          ]
        : categories.take(2).toList(growable: false);
    return _HybridCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Planned - ${_monthLabel(loadedPlan?.month)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              _StatusPill(
                label: '${(progress * 100).round()}% spent',
                color: AppMoney.positiveColor,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatWhole(total, currency),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _ProgressLabel(
            leading: '${_formatWhole(spent, currency)} spent',
            trailing: '${_formatWhole(remaining.abs(), currency)} remaining',
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress, minHeight: 7),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var index = 0; index < primary.length; index++) ...[
                Expanded(
                  child: _MiniBudgetBox(
                    label: primary[index].label,
                    value: _formatWhole(primary[index].amount, currency),
                    color: primary[index].color,
                  ),
                ),
                if (index < primary.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthlyBudgetChartCard extends StatelessWidget {
  const _MonthlyBudgetChartCard({required this.plan, required this.snapshot});

  final MonthlyPlan? plan;
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final loadedPlan = plan;
    final planned = loadedPlan?.totalBudget ?? 12294;
    final spent = loadedPlan?.totalActual ?? 0;
    final remaining = loadedPlan?.totalRemaining ?? planned;
    return _HybridCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Monthly budget - ${_monthLabel(loadedPlan?.month)}',
            actionLabel: 'All months',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            width: double.infinity,
            child: CustomPaint(
              painter: _BudgetLinePainter(
                color: AppMoney.positiveColor,
                actualFraction: planned <= 0
                    ? 0
                    : (spent / planned).clamp(0.0, 1.0),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _MetricStrip(
            metrics: [
              _MetricData(label: 'Planned', value: _formatNumber(planned)),
              _MetricData(label: 'Spent', value: _formatNumber(spent)),
              _MetricData(
                label: 'Remaining',
                value: _formatNumber(remaining.abs()),
                positive: remaining >= 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdownPanel extends StatelessWidget {
  const _CategoryBreakdownPanel({required this.plan});

  final MonthlyPlan? plan;

  @override
  Widget build(BuildContext context) {
    final slices = _plannedCategories(plan);
    final currency = plan?.currency ?? 'NOK';
    final total = slices.fold<double>(0, (sum, item) => sum + item.amount);
    return _HybridCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final chart = SizedBox.square(
            dimension: compact ? 170 : 220,
            child: CustomPaint(
              painter: _DonutPainter(slices: slices),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatNumber(total),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$currency total',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          final legend = Column(
            children: [
              for (var index = 0; index < slices.length; index++) ...[
                _CategoryLegendRow(
                  slice: slices[index],
                  total: total,
                  currency: currency,
                ),
                if (index < slices.length - 1) const Divider(height: 18),
              ],
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                title: compact
                    ? 'Category breakdown'
                    : 'Planned costs by category',
              ),
              const SizedBox(height: 12),
              if (compact)
                Column(children: [chart, const SizedBox(height: 12), legend])
              else
                Row(
                  children: [
                    Expanded(flex: 4, child: Center(child: chart)),
                    const SizedBox(width: 20),
                    Expanded(flex: 6, child: legend),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SpendTrendChartPanel extends StatelessWidget {
  const _SpendTrendChartPanel({required this.items});

  final List<ActivityItem> items;

  @override
  Widget build(BuildContext context) {
    return _HybridCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: '6-month spend trend',
            actionLabel: '-8% vs last month',
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(painter: _TrendLinePainter()),
          ),
          const SizedBox(height: 12),
          Text(
            'Monthly average',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            'NOK 9,840',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _MiniBudgetBox extends StatelessWidget {
  const _MiniBudgetBox({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value.replaceFirst('NOK ', ''),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryLegendRow extends StatelessWidget {
  const _CategoryLegendRow({
    required this.slice,
    required this.total,
    required this.currency,
  });

  final _CategorySlice slice;
  final double total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final percent = total <= 0 ? 0 : (slice.amount / total * 100).round();
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: slice.color,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const SizedBox.square(dimension: 10),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            slice.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatNumber(slice.amount),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: slice.isAlert ? _hybridNegative : null,
              ),
            ),
            Text(
              percent <= 0 ? 'planned' : '$percent%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ignore: unused_element
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

    return _HybridCard(
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

// ignore: unused_element
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

    return _HybridCard(
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
                  : _hybridNegative,
            ),
            _CashflowRowData(
              label: 'Follow-ups',
              amountText: '${snapshot.actionItems.length} items',
              fraction: (snapshot.actionItems.length / 5).clamp(0.12, 1.0),
              color: const Color(0xFFE8A317),
            ),
          ]
        : _cashflowRowsFor(loadedPlan);

    return _HybridCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'Cashflow — ${_monthOnlyLabel(plan?.month)}'),
          const SizedBox(height: 10),
          for (var index = 0; index < rows.length; index++) ...[
            _CashflowBar(row: rows[index]),
            if (index < rows.length - 1) const SizedBox(height: 10),
          ],
          if (loadedPlan != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: _hybridTrack),
            const SizedBox(height: 10),
            _NetSurplusFooter(plan: loadedPlan),
          ],
        ],
      ),
    );
  }

  List<_CashflowRowData> _cashflowRowsFor(MonthlyPlan plan) {
    final income = _cashflowIncome(plan);
    final plannedCosts = plan.totalBudget;
    final loanEmis = _loanAmount(plan);
    final discretionary = (plannedCosts - loanEmis).clamp(0.0, double.infinity);
    final surplus = plan.surplus ?? income - plannedCosts;
    final surplusPositive = surplus >= -0.005;
    final maxAmount = [
      income.abs(),
      plannedCosts.abs(),
      loanEmis.abs(),
      discretionary.abs(),
      surplus.abs(),
    ].fold<double>(1, (max, amount) => amount > max ? amount : max);
    double fraction(double value) => (value.abs() / maxAmount).clamp(0.08, 1.0);
    return [
      _CashflowRowData(
        label: 'Income',
        amountText: _formatWhole(income, plan.currency),
        fraction: fraction(income),
        color: AppMoney.positiveColor,
      ),
      _CashflowRowData(
        label: 'Planned costs',
        amountText: _formatWhole(plannedCosts, plan.currency),
        fraction: fraction(plannedCosts),
        color: _hybridAccent,
      ),
      _CashflowRowData(
        label: 'Loan EMIs',
        amountText: _formatWhole(loanEmis, plan.currency),
        fraction: fraction(loanEmis),
        color: const Color(0xFF7AA2F7),
      ),
      _CashflowRowData(
        label: 'Discretionary',
        amountText: _formatWhole(discretionary, plan.currency),
        fraction: fraction(discretionary),
        color: _hybridExpense,
      ),
      _CashflowRowData(
        label: surplusPositive ? 'Surplus' : 'Shortfall',
        amountText: _formatWhole(surplus.abs(), plan.currency),
        fraction: fraction(surplus),
        color: surplusPositive ? _hybridAccentSoft : _hybridNegativeSoft,
        amountColor: surplusPositive ? AppMoney.positiveColor : _hybridNegative,
      ),
    ];
  }
}

class _NetSurplusFooter extends StatelessWidget {
  const _NetSurplusFooter({required this.plan});

  final MonthlyPlan plan;

  @override
  Widget build(BuildContext context) {
    final surplus = _cashflowSurplus(plan);
    final positive = surplus >= -0.005;
    final amountColor = positive ? AppMoney.positiveColor : _hybridNegative;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            positive
                ? 'Net surplus after all planned costs'
                : 'Net shortfall after all planned costs',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _formatWhole(surplus.abs(), plan.currency),
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: amountColor,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
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

    return _HybridCard(
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

// ignore: unused_element
class _SpendTrendPanel extends StatelessWidget {
  const _SpendTrendPanel({required this.items});

  final List<ActivityItem> items;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(5).toList(growable: false);
    return _HybridCard(
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
    final color = item.positive
        ? AppMoney.positiveColor
        : AppMoney.positiveColor;
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
              backgroundColor: _hybridTrack,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textStyle = Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800);
              final painter = TextPainter(
                maxLines: 1,
                text: TextSpan(text: row.amountText, style: textStyle),
                textDirection: Directionality.of(context),
              )..layout(maxWidth: constraints.maxWidth);
              final filledWidth = constraints.maxWidth * row.fraction;
              final labelFitsInFill = filledWidth >= painter.width + 16;
              final amountColor = row.amountColor == null && labelFitsInFill
                  ? Colors.white
                  : row.amountColor ?? colors.onSurface;

              return ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 22,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: _hybridTrack),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: row.fraction,
                        child: ColoredBox(color: row.color),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            row.amountText,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: textStyle?.copyWith(color: amountColor),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
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
    this.amountColor,
  });

  final String label;
  final String amountText;
  final double fraction;
  final Color color;
  final Color? amountColor;
}

class _CategoryFocusRow extends StatelessWidget {
  const _CategoryFocusRow({required this.category, required this.currency});

  final MonthlyPlanCategory category;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final overBudget = category.overBudget || category.remaining < -0.005;
    final progress = category.budget <= 0
        ? 0.0
        : category.progress.clamp(0.0, 1.0);
    final color = overBudget
        ? _hybridNegative
        : progress >= 0.8
        ? _hybridWarning
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
          LinearProgressIndicator(
            value: progress,
            color: color,
            backgroundColor: _hybridTrack,
          ),
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
        color: const Color(0xFFF7F8F9),
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

    return _HybridCard(
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
                  ? _hybridAccentSoft
                  : _hybridNeutralSoft,
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
    return _HybridCard(
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
                ? _hybridAccentSoft
                : _hybridNegativeSoft,
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
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
          ),
        );
      },
    );
  }
}

class _CategorySlice {
  const _CategorySlice({
    required this.label,
    required this.amount,
    required this.color,
    this.isAlert = false,
  });

  final String label;
  final double amount;
  final Color color;
  final bool isAlert;
}

List<_CategorySlice> _plannedCategories(MonthlyPlan? plan) {
  final source = plan?.categories
      .where((category) => category.budget.abs() > 0.005)
      .take(6)
      .toList(growable: false);
  if (source == null || source.isEmpty) {
    return const [
      _CategorySlice(
        label: 'Rent and housing',
        amount: 8000,
        color: _hybridAccentStrong,
      ),
      _CategorySlice(
        label: 'Loans / EMI',
        amount: 4294,
        color: _hybridAccent,
        isAlert: true,
      ),
      _CategorySlice(
        label: 'Groceries',
        amount: 4200,
        color: Color(0xFF3FBF9B),
      ),
      _CategorySlice(
        label: 'Transport',
        amount: 1800,
        color: Color(0xFF7AA2F7),
      ),
      _CategorySlice(label: 'Utilities', amount: 1200, color: _hybridExpense),
      _CategorySlice(
        label: 'Subscriptions',
        amount: 600,
        color: Color(0xFF9D7CFF),
      ),
    ];
  }
  return [
    for (var index = 0; index < source.length; index++)
      _CategorySlice(
        label: source[index].category,
        amount: source[index].budget.abs(),
        color: _plannedCostColor(source[index].category, index),
        isAlert: _isLoanLikeCategory(source[index].category),
      ),
  ];
}

Color _plannedCostColor(String category, int index) {
  final normalized = category.trim().toLowerCase();
  if (_isLoanLikeCategory(category)) {
    return _hybridAccent;
  }
  if (normalized.contains('rent') ||
      normalized.contains('housing') ||
      normalized.contains('home')) {
    return _hybridAccentStrong;
  }
  if (normalized.contains('grocery') ||
      normalized.contains('food') ||
      normalized.contains('rema')) {
    return const Color(0xFF3FBF9B);
  }
  if (normalized.contains('transport') ||
      normalized.contains('fuel') ||
      normalized.contains('pass')) {
    return const Color(0xFF7AA2F7);
  }
  if (normalized.contains('subscription') ||
      normalized.contains('membership')) {
    return const Color(0xFF9D7CFF);
  }
  const colors = [
    _hybridAccentStrong,
    _hybridAccent,
    Color(0xFF3FBF9B),
    Color(0xFF7AA2F7),
    _hybridExpense,
    Color(0xFF9D7CFF),
  ];
  return colors[index % colors.length];
}

String _formatWhole(num amount, String currency) {
  return '$currency ${_formatNumber(amount)}';
}

String _formatNumber(num amount) {
  final rounded = amount.round().abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < rounded.length; index++) {
    final remaining = rounded.length - index;
    buffer.write(rounded[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

class _BudgetLinePainter extends CustomPainter {
  const _BudgetLinePainter({required this.color, required this.actualFraction});

  final Color color;
  final double actualFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;
    for (var i = 0; i <= 6; i++) {
      final y = size.height * i / 6;
      canvas.drawLine(Offset(40, y), Offset(size.width, y), gridPaint);
    }

    final fillPath = Path()
      ..moveTo(40, size.height * 0.2)
      ..lineTo(size.width, size.height * 0.86)
      ..lineTo(size.width, size.height)
      ..lineTo(40, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = const Color(0xFFEAF6F1));

    final planned = Path()
      ..moveTo(40, size.height * 0.2)
      ..lineTo(size.width, size.height * 0.86);
    final plannedPaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    _drawDashedPath(canvas, planned, plannedPaint);

    final actualX = 40 + (size.width - 40) * actualFraction.clamp(0.02, 0.98);
    final actualY = size.height * (0.2 + 0.66 * actualFraction);
    canvas.drawCircle(Offset(actualX, actualY), 6, Paint()..color = color);
    canvas.drawLine(
      Offset(40, size.height * 0.2),
      Offset(actualX, actualY),
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );
    const labels = ['14k', '12k', '10k', '8k', '6k', '4k', '0k'];
    for (var i = 0; i < labels.length; i++) {
      textPainter.text = TextSpan(
        text: 'NOK ${labels[i]}',
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
      );
      textPainter.layout(maxWidth: 38);
      textPainter.paint(canvas, Offset(0, size.height * i / 6 - 6));
    }
  }

  @override
  bool shouldRepaint(covariant _BudgetLinePainter oldDelegate) {
    return oldDelegate.actualFraction != actualFraction ||
        oldDelegate.color != color;
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.slices});

  final List<_CategorySlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (sum, item) => sum + item.amount);
    if (total <= 0) return;
    final rect = Offset.zero & size;
    final strokeWidth = size.shortestSide * 0.16;
    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = math.pi * 2 * (slice.amount / total);
      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(
        rect.deflate(strokeWidth / 2),
        start,
        sweep - 0.035,
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.slices != slices;
  }
}

class _TrendLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = 20 + i * (size.height - 44) / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final points = [
      Offset(0, size.height * 0.32),
      Offset(size.width * 0.18, size.height * 0.36),
      Offset(size.width * 0.38, size.height * 0.46),
      Offset(size.width * 0.58, size.height * 0.42),
      Offset(size.width * 0.75, size.height * 0.36),
      Offset(size.width, size.height * 0.78),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      path.lineTo(points[index].dx, points[index].dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height - 18)
      ..lineTo(0, size.height - 18)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0xFFEAF6F1));
    canvas.drawPath(
      path,
      Paint()
        ..color = AppMoney.positiveColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke,
    );
    for (final point in points.take(points.length - 1)) {
      canvas.drawCircle(point, 3.5, Paint()..color = AppMoney.positiveColor);
      canvas.drawCircle(point, 2, Paint()..color = Colors.white);
    }
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    const labels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
    for (var index = 0; index < labels.length; index++) {
      labelPainter.text = TextSpan(
        text: labels[index],
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(
          (size.width - 20) * index / (labels.length - 1),
          size.height - 12,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) => false;
}

void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + 6, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance += 12;
    }
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

String _monthOnlyLabel(String? value) {
  return _monthLabel(value).split(' ').first;
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

double _cashflowIncome(MonthlyPlan plan) {
  final explicitIncome = plan.income;
  if (explicitIncome != null && explicitIncome.abs() > 0.005) {
    return explicitIncome;
  }
  if (plan.totalBudget > 0.005) {
    return 36000;
  }
  return 0;
}

double _cashflowSurplus(MonthlyPlan plan) {
  return plan.surplus ?? _cashflowIncome(plan) - plan.totalBudget;
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
          _StatusPill(label: badge!, color: _hybridNegative)
        else if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: _hybridAccentStrong),
            child: Text(actionLabel!),
          ),
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
        color: _pillBackgroundFor(context, color),
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

Color _pillBackgroundFor(BuildContext context, Color color) {
  if (color == AppMoney.positiveColor) {
    return _hybridAccentSoft;
  }
  if (color == _hybridWarning || color == _hybridWarningText) {
    return _hybridWarningSoft;
  }
  if (color == _hybridNegative ||
      color == Theme.of(context).colorScheme.error) {
    return _hybridNegativeSoft;
  }
  return _hybridNeutralSoft;
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
    _InsightTone.warning => _hybridWarning,
    _InsightTone.critical => _hybridNegative,
    _InsightTone.neutral => colors.onSurfaceVariant,
  };
}

Color _backgroundFor(BuildContext context, _InsightTone tone) {
  return switch (tone) {
    _InsightTone.positive => _hybridAccentSoft,
    _InsightTone.warning => _hybridWarningSoft,
    _InsightTone.critical => _hybridNegativeSoft,
    _InsightTone.neutral => _hybridNeutralSoft,
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
