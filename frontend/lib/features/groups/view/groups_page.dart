import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GroupsPage extends StatelessWidget {
  const GroupsPage({super.key});

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
                if (snapshot.groupItems.isEmpty)
                  const _GroupTile(
                    title: 'No groups yet',
                    subtitle: 'Create a group to split expenses with others.',
                    trailing: 'Create group',
                  ),
                ...snapshot.groupItems.map(
                  (item) => _GroupTile(
                    title: item.title,
                    subtitle: item.subtitle,
                    trailing: item.amountText,
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

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.group_outlined),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Text(trailing, style: Theme.of(context).textTheme.labelLarge),
      ),
    );
  }
}
