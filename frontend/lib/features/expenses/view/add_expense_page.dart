import 'dart:async';

import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/utils/platform_widget.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AddExpensePage extends StatefulWidget {
  const AddExpensePage({this.expense, super.key});

  final Expense? expense;

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _editing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    if (expense != null) {
      _descriptionController.text = expense.description ?? expense.title;
      _amountController.text = expense.amount.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final description = _descriptionController.text.trim();
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);

    if (description.isEmpty) {
      setState(() => _error = 'Description is required.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount greater than 0.');
      return;
    }

    final existing = widget.expense;
    final expense = Expense(
      core: ExpenseCore(
        id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: description,
        amount: amount,
        currency: existing?.currency ?? 'INR',
        category: existing?.category ?? 'Personal',
        createdAt: existing?.createdAt ?? DateTime.now(),
      ),
      description: description,
      paymentMethod: existing?.paymentMethod ?? 'cash',
      updatedAt: DateTime.now(),
      isSynced: false,
      deleted: existing?.deleted ?? false,
    );

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final bloc = context.read<ExpensesBloc>();
      if (_editing) {
        bloc.add(UpdateExpense(expense: expense));
      } else {
        bloc.add(CreateExpense(expense: expense));
      }

      final resultState = await bloc.stream
          .firstWhere(
            (state) => state is ExpensesLoaded || state is ExpensesError,
          )
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;

      if (resultState is ExpensesError) {
        setState(() {
          _saving = false;
          _error = resultState.message;
        });
        return;
      }

      Navigator.of(context).pop(true);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'Timed out while saving expense. Please check backend connectivity and try again.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlatformWidget(
      ios: _buildCupertino(context),
      android: _buildMaterial(context),
      web: _buildMaterial(context),
    );
  }

  Widget _buildMaterial(BuildContext context) {
    final title = _editing ? 'Edit expense' : 'Add an expense';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AppPageContainer(
        maxWidth: 760,
        children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'With you and',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [Chip(label: Text('Just you'))],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: AppMoney.inputPrefix,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ReadonlySelector(label: 'Paid by', value: 'You'),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: _ReadonlySelector(
                        label: 'Split',
                        value: 'Personal',
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Save expense'),
          ),
        ],
      ),
    );
  }

  Widget _buildCupertino(BuildContext context) {
    final title = _editing ? 'Edit expense' : 'Add an expense';
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(30, 30),
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ),
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Text(
                    'With you and',
                    style: CupertinoTheme.of(
                      context,
                    ).textTheme.navTitleTextStyle,
                  ),
                  const SizedBox(height: 10),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [Chip(label: Text('Just you'))],
                  ),
                  const SizedBox(height: 12),
                  CupertinoFormSection.insetGrouped(
                    children: [
                      CupertinoFormRow(
                        prefix: const Text('Description'),
                        child: CupertinoTextField(
                          controller: _descriptionController,
                          placeholder: 'Enter a description',
                          textAlign: TextAlign.end,
                        ),
                      ),
                      CupertinoFormRow(
                        prefix: const Text('Amount'),
                        child: CupertinoTextField(
                          controller: _amountController,
                          placeholder: 'INR 0.00',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      const CupertinoFormRow(
                        prefix: Text('Paid by'),
                        child: Text('You', textAlign: TextAlign.end),
                      ),
                      const CupertinoFormRow(
                        prefix: Text('Split'),
                        child: Text('Personal', textAlign: TextAlign.end),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: CupertinoTheme.of(context).primaryColor,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  CupertinoButton.filled(
                    onPressed: _saving ? null : _save,
                    child: const Text('Save expense'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadonlySelector extends StatelessWidget {
  const _ReadonlySelector({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.chevron_right),
      ),
      child: Text(value),
    );
  }
}
