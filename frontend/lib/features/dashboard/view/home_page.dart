import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:expense_tracker/features/dashboard/view/dashboard_overall_summary_card.dart';
import 'package:expense_tracker/features/planning/view/monthly_planning_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    this.onOpenFriends,
    this.onOpenGroups,
    this.autoRefresh = false,
    super.key,
  });

  final VoidCallback? onOpenFriends;
  final VoidCallback? onOpenGroups;
  final bool autoRefresh;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DashboardSnapshotCubit>().state;
    final dashboardCubit = context.read<DashboardSnapshotCubit>();
    Future<void> refreshDashboard() => dashboardCubit.load(showLoading: false);
    if (state is DashboardSnapshotFailure) {
      return AppPageContainer(
        onRefresh: refreshDashboard,
        autoRefresh: autoRefresh,
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
      onRefresh: refreshDashboard,
      autoRefresh: autoRefresh,
      children: [
        const DashboardOverallSummaryCard(),
        const SizedBox(height: 16),
        const MonthlyPlanningCard(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _MiniSummaryCard(
                title: 'Friends',
                items: snapshot.friendItems,
                emptyText: 'No friend balances yet',
                onTap: onOpenFriends,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniSummaryCard(
                title: 'Groups',
                items: snapshot.groupItems,
                emptyText: 'No group balances yet',
                onTap: onOpenGroups,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const AppSectionHeader(title: 'Recent activity'),
        if (snapshot.activityItems.isEmpty)
          const AppEmptyState(
            title: 'Nothing to show yet',
            subtitle: 'Add an expense or upload a bill to start your timeline.',
          )
        else
          ...snapshot.activityItems.take(5).map(_RecentActivityTile.new),
      ],
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
