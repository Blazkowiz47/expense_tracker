import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

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

        final snapshot = state.snapshot;
        final settledUp = snapshot.overallLabel.toLowerCase().contains(
          'settled',
        );
        final isCredit = snapshot.overallPositive;
        final title = settledUp
            ? 'You are all settled up'
            : (isCredit ? 'You are in credit' : 'You are in debt');
        final subtitle = settledUp
            ? 'No one owes you and you do not owe anyone.'
            : (isCredit
                  ? 'You should receive money overall.'
                  : 'You owe money overall.');

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.overallAmountText,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: settledUp
                                    ? Theme.of(context).colorScheme.primary
                                    : isCredit
                                    ? const Color(0xFF1B8C67)
                                    : Theme.of(context).colorScheme.error,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                BlocBuilder<ExpensesBloc, ExpensesState>(
                  builder: (context, expenseState) {
                    if (expenseState is ExpensesLoading ||
                        expenseState is ExpensesInitial ||
                        expenseState is ExpensesRefreshing) {
                      return const Card(
                        child: ListTile(
                          title: Text('Personal expenses'),
                          subtitle: Text('Loading...'),
                        ),
                      );
                    }
                    if (expenseState is ExpensesError) {
                      return Card(
                        child: ListTile(
                          title: const Text('Personal expenses'),
                          subtitle: Text(expenseState.message),
                        ),
                      );
                    }
                    final expenses = expenseState is ExpensesLoaded
                        ? expenseState.expenses
                              .where((e) => !e.deleted)
                              .toList()
                        : expenseState is SyncSuccess
                        ? expenseState.expenses
                              .where((e) => !e.deleted)
                              .toList()
                        : const [];
                    final total = expenses.fold<double>(
                      0,
                      (sum, expense) => sum + expense.amount,
                    );
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Personal expenses',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'INR ${total.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total spent',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 10),
                            if (expenses.isEmpty)
                              const Text(
                                'No personal expenses yet. Tap Add expense to create one.',
                              )
                            else
                              ...expenses
                                  .toList()
                                  .reversed
                                  .take(6)
                                  .map(
                                    (expense) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(expense.title),
                                      subtitle: Text(
                                        expense.createdAt
                                            .toLocal()
                                            .toString()
                                            .split('.')
                                            .first,
                                      ),
                                      trailing: Text(
                                        'INR ${expense.amount.toStringAsFixed(2)}',
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
