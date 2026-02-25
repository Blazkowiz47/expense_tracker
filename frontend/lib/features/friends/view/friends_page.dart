import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardSnapshotCubit, DashboardSnapshotState>(
      builder: (context, state) {
        if (state is DashboardSnapshotFailure) {
          return Center(child: Text(state.message));
        }

        if (state is! DashboardSnapshotLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final snapshot = state.snapshot;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryCard(
                  title: snapshot.overallLabel,
                  amount: snapshot.overallAmountText,
                  amountColor: snapshot.overallPositive
                      ? const Color(0xFF1B8C67)
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                const _ListSectionHeader(
                  title: 'Friends',
                  actionLabel: 'Add friend',
                ),
                if (snapshot.friendItems.isEmpty)
                  const _BalanceTile(
                    name: 'No friends yet',
                    subtitle: 'Your friend balances will appear here.',
                    amount: 'Add your first friend',
                    amountColor: Color(0xFF58646F),
                  ),
                ...snapshot.friendItems.map(
                  (item) => _BalanceTile(
                    name: item.title,
                    subtitle: item.subtitle,
                    amount: item.amountText,
                    amountColor: item.positive
                        ? const Color(0xFF1B8C67)
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.amountColor,
  });

  final String title;
  final String amount;
  final Color amountColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              amount,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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

class _ListSectionHeader extends StatelessWidget {
  const _ListSectionHeader({required this.title, required this.actionLabel});

  final String title;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          TextButton(onPressed: () {}, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.name,
    required this.subtitle,
    required this.amount,
    required this.amountColor,
  });

  final String name;
  final String subtitle;
  final String amount;
  final Color amountColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.person_outline),
        ),
        title: Text(name),
        subtitle: Text(subtitle),
        trailing: Text(
          amount,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: amountColor),
        ),
      ),
    );
  }
}
