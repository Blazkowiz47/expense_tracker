import 'dart:async';

import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/recurring/models/recurring_template.dart';
import 'package:expense_tracker/features/recurring/repositories/api_recurring_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  Future<void> _editPersonalExpense(
    BuildContext context,
    Expense expense,
  ) async {
    final descriptionController = TextEditingController(text: expense.title);
    final amountController = TextEditingController(
      text: expense.amount.toStringAsFixed(2),
    );
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit personal expense'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: 'INR ',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop({
              'description': descriptionController.text.trim(),
              'amount': double.tryParse(amountController.text.trim()),
            }),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (payload == null || !context.mounted) return;

    final description = (payload['description'] as String?) ?? '';
    final amount = payload['amount'] as double?;
    if (description.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid description and amount.')),
      );
      return;
    }

    final updated = expense.copyWith(
      core: ExpenseCore(
        id: expense.id,
        title: description,
        amount: amount,
        currency: expense.currency,
        category: expense.category,
        createdAt: expense.createdAt,
      ),
      description: description,
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    final bloc = context.read<ExpensesBloc>();
    bloc.add(UpdateExpense(expense: updated));
    try {
      final resultState = await bloc.stream
          .firstWhere(
            (state) => state is ExpensesLoaded || state is ExpensesError,
          )
          .timeout(const Duration(seconds: 20));
      if (!context.mounted) return;
      if (resultState is ExpensesError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(resultState.message)));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Expense updated.')));
    } on TimeoutException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updating expense timed out.')),
      );
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
        final expensesBloc = context.read<ExpensesBloc?>();

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
                if (expensesBloc == null)
                  const Card(
                    child: ListTile(
                      title: Text('Personal expenses'),
                      subtitle: Text('Expenses data unavailable in this view.'),
                    ),
                  )
                else
                  BlocBuilder<ExpensesBloc, ExpensesState>(
                    bloc: expensesBloc,
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
                                        onTap: () => _editPersonalExpense(
                                          context,
                                          expense,
                                        ),
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
                const SizedBox(height: 12),
                const _RecurringOverviewCard(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecurringOverviewCard extends StatefulWidget {
  const _RecurringOverviewCard();

  @override
  State<_RecurringOverviewCard> createState() => _RecurringOverviewCardState();
}

class _RecurringOverviewCardState extends State<_RecurringOverviewCard> {
  late final http.Client _client;
  late final ApiRecurringRepository _repository;
  List<RecurringTemplate> _templates = const [];
  bool _loading = true;
  bool _processingDue = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = http.Client();
    _repository = ApiRecurringRepository(client: _client);
    _load();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final templates = await _repository.fetchTemplates();
      if (!mounted) return;
      setState(() => _templates = templates.where((t) => t.active).toList());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createTemplate() async {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final categoryController = TextEditingController(text: 'Utilities');
    String selectedFrequency = 'monthly';
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add recurring template'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: 'INR ',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedFrequency,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => selectedFrequency = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(<String, dynamic>{
                'title': titleController.text.trim(),
                'amount': double.tryParse(amountController.text.trim()),
                'category': categoryController.text.trim(),
                'frequency': selectedFrequency,
              }),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (payload == null) return;
    final title = (payload['title'] as String?) ?? '';
    final category = (payload['category'] as String?) ?? '';
    final frequency = (payload['frequency'] as String?) ?? 'monthly';
    final amount = payload['amount'] as double?;
    if (title.isEmpty || category.isEmpty || amount == null || amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter valid title, category and positive amount.'),
        ),
      );
      return;
    }
    try {
      await _repository.createTemplate(
        title: title,
        amount: amount,
        category: category,
        frequency: frequency,
        startDate: DateTime.now(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recurring template created.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _processDue() async {
    if (_processingDue) return;
    setState(() => _processingDue = true);
    try {
      final created = await _repository.processDueTemplates();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Generated $created due expense(s).')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _processingDue = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String subtitle = 'Track recurring payments like rent or subscriptions.';
    if (_loading) {
      subtitle = 'Loading recurring templates...';
    } else if (_error != null) {
      subtitle = 'Could not load recurring templates.';
    } else if (_templates.isEmpty) {
      subtitle = 'No recurring templates yet.';
    } else {
      final sorted = [..._templates]
        ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
      final next = sorted.first;
      subtitle =
          '${_templates.length} active • Next due ${next.nextDueDate.toLocal().toString().split(' ').first}';
    }
    return Card(
      child: ListTile(
        title: const Text('Recurring payments'),
        subtitle: Text(subtitle),
        trailing: _loading || _processingDue
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: _load, child: const Text('Refresh')),
                  OutlinedButton(
                    onPressed: _processDue,
                    child: const Text('Process due'),
                  ),
                  FilledButton.tonal(
                    onPressed: _createTemplate,
                    child: const Text('Add'),
                  ),
                ],
              ),
      ),
    );
  }
}
