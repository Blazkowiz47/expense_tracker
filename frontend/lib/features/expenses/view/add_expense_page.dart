import 'dart:async';

import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/utils/date_formatter.dart';
import 'package:expense_tracker/core/utils/platform_widget.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/expenses/repositories/bill_ai_repository.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

class AddExpensePage extends StatefulWidget {
  const AddExpensePage({
    this.expense,
    this.initialBillUpload = false,
    super.key,
  });

  final Expense? expense;
  final bool initialBillUpload;

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  static const _categories = <String>[
    'Food',
    'Groceries',
    'Transport',
    'Shopping',
    'Bills',
    'Travel',
    'Health',
    'Personal',
  ];
  static const _currencies = <String>['INR', 'NOK', 'USD', 'EUR', 'GBP'];
  static const _paymentMethods = <String>[
    'cash',
    'card',
    'upi',
    'bank_transfer',
    'other',
  ];

  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _billRepository = BillAiRepository();
  final _picker = ImagePicker();

  bool _saving = false;
  bool _extractingBill = false;
  String? _error;
  String? _billMessage;
  BillExtractionResult? _billResult;
  DateTime _expenseDate = DateTime.now();
  String _category = 'Personal';
  String _currency = 'INR';
  String _paymentMethod = 'cash';

  bool get _editing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    if (expense != null) {
      final descriptionParts = _splitDescription(
        expense.description,
        expense.title,
      );
      _descriptionController.text = descriptionParts.title;
      _notesController.text = descriptionParts.notes;
      _amountController.text = expense.amount.toStringAsFixed(2);
      _expenseDate = expense.createdAt;
      _category = _normalizedChoice(
        expense.category ?? 'Personal',
        _categories,
        'Personal',
      );
      _currency = _normalizedChoice(expense.currency, _currencies, 'INR');
      _paymentMethod = _normalizedChoice(
        expense.paymentMethod ?? 'cash',
        _paymentMethods,
        'cash',
      );
    }
    if (widget.initialBillUpload && expense == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _uploadBill();
        }
      });
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save({bool addAnother = false}) async {
    final description = _descriptionController.text.trim();
    final amountText = _amountController.text.trim();
    final amount = _parseAmount(amountText);

    if (description.isEmpty) {
      setState(() => _error = 'Description is required.');
      return;
    }
    if (amount == null || !amount.isFinite || amount <= 0) {
      setState(() => _error = 'Enter a valid amount greater than 0.');
      return;
    }

    final notes = _notesController.text.trim();
    final existing = widget.expense;
    final expense = Expense(
      core: ExpenseCore(
        id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: description,
        amount: amount,
        currency: _currency,
        category: _category,
        createdAt: _expenseDate,
      ),
      description: _composeDescription(description, notes),
      paymentMethod: _paymentMethod,
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

      if (addAnother && !_editing) {
        setState(() {
          _saving = false;
          _descriptionController.clear();
          _amountController.clear();
          _notesController.clear();
          _billResult = null;
          _billMessage = 'Saved. Ready for the next expense.';
          _expenseDate = DateTime.now();
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

  Future<void> _uploadBill() async {
    setState(() {
      _extractingBill = true;
      _error = null;
      _billMessage = 'Extracting bill on the backend...';
    });
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null) {
        setState(() {
          _extractingBill = false;
          _billMessage = null;
        });
        return;
      }
      final result = await _billRepository.uploadAndWait(
        bytes: await picked.readAsBytes(),
        fileName: picked.name,
        contentType: _contentTypeFor(picked.name),
      );
      if (!mounted) return;
      final primaryDescription = result.merchant.isNotEmpty
          ? result.merchant
          : result.notes;
      _descriptionController.text = primaryDescription;
      _notesController.text = result.notes.trim() == primaryDescription.trim()
          ? ''
          : result.notes;
      if (result.amount > 0) {
        _amountController.text = result.amount.toStringAsFixed(2);
      }
      setState(() {
        _billResult = result;
        _expenseDate = result.date;
        _category = _normalizedChoice(result.category, _categories, 'Personal');
        _currency = _normalizedChoice(result.currency, _currencies, 'INR');
        _extractingBill = false;
        _billMessage =
            'Bill autofill ready (${(result.confidence * 100).toStringAsFixed(0)}% confidence).';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _extractingBill = false;
        _error = 'Bill extraction failed: $error';
        _billMessage = null;
      });
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _expenseDate = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _expenseDate.hour,
        _expenseDate.minute,
      );
    });
  }

  Future<void> _showCupertinoChoice({
    required String title,
    required List<String> values,
    required String selectedValue,
    required ValueChanged<String> onSelected,
    String Function(String value)? labelFor,
  }) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(title),
        actions: values
            .map(
              (value) => CupertinoActionSheetAction(
                isDefaultAction: value == selectedValue,
                onPressed: () {
                  Navigator.of(context).pop();
                  onSelected(value);
                },
                child: Text(labelFor?.call(value) ?? value),
              ),
            )
            .toList(growable: false),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  String _contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  double? _parseAmount(String value) {
    var normalized = value.trim().replaceAll(' ', '');
    if (normalized.contains(',') && normalized.contains('.')) {
      normalized = normalized.replaceAll(',', '');
    } else if (normalized.contains(',')) {
      final parts = normalized.split(',');
      if (parts.length == 2 && parts.last.length == 3) {
        normalized = '${parts.first}${parts.last}';
      } else {
        normalized = normalized.replaceAll(',', '.');
      }
    }
    return double.tryParse(normalized);
  }

  ({String title, String notes}) _splitDescription(
    String? description,
    String fallbackTitle,
  ) {
    final raw = (description?.trim().isNotEmpty == true
        ? description!.trim()
        : fallbackTitle.trim());
    if (raw.isEmpty) {
      return (title: fallbackTitle, notes: '');
    }
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return (title: fallbackTitle, notes: '');
    }
    return (
      title: lines.first,
      notes: lines.length <= 1 ? '' : lines.skip(1).join('\n'),
    );
  }

  String _composeDescription(String description, String notes) {
    if (notes.isEmpty || notes == description) {
      return description;
    }
    return '$description\n$notes';
  }

  String _normalizedChoice(
    String value,
    List<String> choices,
    String fallback,
  ) {
    final lower = value.trim().toLowerCase();
    return choices.firstWhere(
      (choice) => choice.toLowerCase() == lower,
      orElse: () => fallback,
    );
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
                  'Expense details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _BillUploadButton(
                  extracting: _extractingBill,
                  saving: _saving,
                  onPressed: _uploadBill,
                ),
                if (_billMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(_billMessage!),
                ],
                if (_billResult != null) ...[
                  const SizedBox(height: 12),
                  _BillReviewPanel(result: _billResult!),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Merchant or description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          prefixText: '$_currency ',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 130,
                      child: _DropdownField(
                        label: 'Currency',
                        value: _currency,
                        values: _currencies,
                        onChanged: (value) => setState(() => _currency = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DropdownField(
                        label: 'Category',
                        value: _category,
                        values: _categories,
                        onChanged: (value) => setState(() => _category = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DropdownField(
                        label: 'Payment',
                        value: _paymentMethod,
                        values: _paymentMethods,
                        labelFor: _paymentLabel,
                        onChanged: (value) =>
                            setState(() => _paymentMethod = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories
                      .map(
                        (category) => ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionSelector(
                        label: 'Date',
                        value: DateFormatter.formatDate(_expenseDate),
                        icon: Icons.calendar_today,
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: _StaticSelector(
                        label: 'Split',
                        value: 'Personal',
                        icon: Icons.person_outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
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
          const SizedBox(height: 72),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Row(
            children: [
              if (!_editing) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(addAnother: true),
                    icon: const Icon(Icons.add),
                    label: const Text('Save + another'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Save expense'),
                ),
              ),
            ],
          ),
        ),
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
                  _BillUploadButton(
                    extracting: _extractingBill,
                    saving: _saving,
                    onPressed: _uploadBill,
                  ),
                  if (_billMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(_billMessage!),
                  ],
                  if (_billResult != null) ...[
                    const SizedBox(height: 12),
                    _BillReviewPanel(result: _billResult!),
                  ],
                  const SizedBox(height: 12),
                  CupertinoFormSection.insetGrouped(
                    children: [
                      CupertinoFormRow(
                        prefix: const Text('Description'),
                        child: CupertinoTextField(
                          controller: _descriptionController,
                          placeholder: 'Merchant or description',
                          textAlign: TextAlign.end,
                        ),
                      ),
                      CupertinoFormRow(
                        prefix: const Text('Amount'),
                        child: CupertinoTextField(
                          controller: _amountController,
                          placeholder: '0.00',
                          prefix: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text('$_currency '),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      CupertinoFormRow(
                        prefix: const Text('Currency'),
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => _showCupertinoChoice(
                            title: 'Currency',
                            values: _currencies,
                            selectedValue: _currency,
                            onSelected: (value) {
                              if (!mounted) return;
                              setState(() => _currency = value);
                            },
                          ),
                          child: Text(_currency, textAlign: TextAlign.end),
                        ),
                      ),
                      CupertinoFormRow(
                        prefix: const Text('Category'),
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => _showCupertinoChoice(
                            title: 'Category',
                            values: _categories,
                            selectedValue: _category,
                            onSelected: (value) {
                              if (!mounted) return;
                              setState(() => _category = value);
                            },
                          ),
                          child: Text(_category, textAlign: TextAlign.end),
                        ),
                      ),
                      CupertinoFormRow(
                        prefix: const Text('Date'),
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: _pickDate,
                          child: Text(DateFormatter.formatDate(_expenseDate)),
                        ),
                      ),
                      CupertinoFormRow(
                        prefix: const Text('Payment'),
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => _showCupertinoChoice(
                            title: 'Payment',
                            values: _paymentMethods,
                            selectedValue: _paymentMethod,
                            labelFor: _paymentLabel,
                            onSelected: (value) {
                              if (!mounted) return;
                              setState(() => _paymentMethod = value);
                            },
                          ),
                          child: Text(
                            _paymentLabel(_paymentMethod),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: _notesController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
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

  static String _paymentLabel(String value) {
    return switch (value) {
      'cash' => 'Cash',
      'card' => 'Card',
      'upi' => 'UPI',
      'bank_transfer' => 'Bank transfer',
      _ => 'Other',
    };
  }
}

class _BillUploadButton extends StatelessWidget {
  const _BillUploadButton({
    required this.extracting,
    required this.saving,
    required this.onPressed,
  });

  final bool extracting;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: saving || extracting ? null : onPressed,
      icon: extracting
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.receipt_long),
      label: Text(extracting ? 'Reading bill...' : 'Upload bill'),
    );
  }
}

class _BillReviewPanel extends StatelessWidget {
  const _BillReviewPanel({required this.result});

  final BillExtractionResult result;

  @override
  Widget build(BuildContext context) {
    final confidence = (result.confidence * 100).toStringAsFixed(0);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Autofill review',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text('$confidence%'),
              ],
            ),
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...result.warnings.map(
                (warning) => Text(
                  warning,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            if (result.lineItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Line items', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              ...result.lineItems
                  .take(4)
                  .map(
                    (item) => Text(
                      [
                        item.name,
                        if (item.quantity?.isNotEmpty == true)
                          'x${item.quantity}',
                        if (item.amount != null)
                          '${result.currency} ${item.amount!.toStringAsFixed(2)}',
                      ].join(' · '),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.labelFor,
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  final String Function(String value)? labelFor;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: values
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(labelFor?.call(item) ?? item),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _ActionSelector extends StatelessWidget {
  const _ActionSelector({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: Icon(icon),
        ),
        child: Text(value),
      ),
    );
  }
}

class _StaticSelector extends StatelessWidget {
  const _StaticSelector({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: Icon(icon),
      ),
      child: Text(value),
    );
  }
}
