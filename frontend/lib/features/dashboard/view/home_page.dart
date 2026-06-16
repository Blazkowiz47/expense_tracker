import 'dart:async';

import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/data/repositories/freshness_repository.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:expense_tracker/features/dashboard/view/dashboard_overall_summary_card.dart';
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
      onRefresh: () => _refreshDashboard(dashboardCubit),
      onAutoRefresh: () => _autoRefreshDashboard(dashboardCubit),
      autoRefresh: widget.autoRefresh,
      children: [
        const DashboardOverallSummaryCard(),
        const SizedBox(height: 16),
        MonthlyPlanningCard(
          title: 'This month',
          repository: widget.monthlyPlanRepository,
          refreshToken: _planRefreshToken,
          onAddExpenseForCategory: widget.onAddExpenseForCategory,
          onReviewCategory: widget.onOpenActivityCategory,
        ),
        const SizedBox(height: 16),
        _DailyActionCenterCard(
          items: snapshot.actionItems,
          onOpenFriends: widget.onOpenFriends,
          onOpenGroups: widget.onOpenGroups,
          onOpenFamily: widget.onOpenFamily,
          onOpenRecurring: widget.onOpenRecurring,
          onOpenAction: widget.onOpenAction,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _MiniSummaryCard(
                title: 'Friends',
                items: snapshot.friendItems,
                emptyText: 'No balances with friends yet',
                onTap: widget.onOpenFriends,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniSummaryCard(
                title: 'Split groups',
                items: snapshot.groupItems,
                emptyText: 'No split-group balances yet',
                onTap: widget.onOpenGroups,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const AppSectionHeader(title: 'Recent activity'),
        if (snapshot.activityItems.isEmpty)
          const AppEmptyState(
            title: 'No activity yet',
            subtitle:
                'Add an expense or scan a receipt to start this month\'s timeline.',
          )
        else
          ...snapshot.activityItems.take(5).map(_RecentActivityTile.new),
      ],
    );
  }
}

class _DailyActionCenterCard extends StatelessWidget {
  const _DailyActionCenterCard({
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
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                icon: Icons.today_outlined,
                backgroundColor: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Today',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No follow-ups today',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Recurring reminders, receipt reviews, and shared-balance nudges will show up here.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          else
            ...items.take(5).map((item) {
              return _DailyActionTile(item: item, onTap: _tapFor(item));
            }),
        ],
      ),
    );
  }

  VoidCallback? _tapFor(DailyActionItem item) {
    if (onOpenAction != null) {
      return () => onOpenAction!(item);
    }
    switch (item.destination) {
      case 'friends':
        return onOpenFriends;
      case 'groups':
        return onOpenGroups;
      case 'family':
        return onOpenFamily;
      case 'recurring':
        return onOpenRecurring;
    }
    return null;
  }
}

class _DailyActionTile extends StatelessWidget {
  const _DailyActionTile({required this.item, this.onTap});

  final DailyActionItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.severity) {
      'critical' => Theme.of(context).colorScheme.error,
      'warning' => Colors.orange.shade700,
      _ => Theme.of(context).colorScheme.primary,
    };
    final icon = switch (item.severity) {
      'critical' => Icons.error_outline,
      'warning' => Icons.event_busy_outlined,
      _ => Icons.task_alt_outlined,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: item.subtitle.isEmpty
          ? null
          : Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: onTap == null
          ? null
          : Icon(
              Icons.arrow_forward,
              size: 18,
              color: Theme.of(context).colorScheme.outline,
            ),
      onTap: onTap,
    );
  }
}

class _MiniSummaryCard extends StatelessWidget {
  const _MiniSummaryCard({
    required this.title,
    required this.items,
    required this.emptyText,
    this.onTap,
  });

  final String title;
  final List<BalanceItem> items;
  final String emptyText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final first = items.isEmpty ? null : items.first;
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: Theme.of(context).colorScheme.outline,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            first?.amountText ?? emptyText,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(first?.title ?? 'All clear'),
        ],
      ),
    );
  }
}

class _RecentActivityTile extends StatelessWidget {
  const _RecentActivityTile(this.item);

  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ListTile(
        leading: AppAvatar(icon: Icons.receipt_long_outlined),
        title: Text(item.title),
        subtitle: Text(item.subtitle),
        trailing: Text(
          AppMoney.normalizeDisplayText(item.amountText),
          style: TextStyle(
            color: AppMoney.statusColor(context, positive: item.positive),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
