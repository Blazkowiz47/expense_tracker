import 'dart:async';

import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/utils/date_formatter.dart';
import 'package:expense_tracker/core/utils/platform_widget.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/expenses/repositories/bill_ai_repository.dart';
import 'package:expense_tracker/features/receipts/widgets/receipt_line_items_review.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

class AddExpensePage extends StatefulWidget {
  const AddExpensePage({
    this.expense,
    this.initialBillUpload = false,
    this.initialCategory,
    this.initialDescription,
    this.initialAmount,
    this.initialCurrency,
    this.initialPaymentMethod,
    super.key,
  });

  final Expense? expense;
  final bool initialBillUpload;
  final String? initialCategory;
  final String? initialDescription;
  final double? initialAmount;
  final String? initialCurrency;
  final String? initialPaymentMethod;

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  static const _categories = <String>[
    'Food',
    'Groceries',
    'Rent and housing',
    'Utilities',
    'Subscriptions',
    'Memberships',
    'Transport',
    'Loans / EMI',
    'Shopping',
    'Bills',
    'Travel',
    'Health',
    'Savings',
    'Personal',
  ];
  static const _currencies = <String>['INR', 'NOK', 'USD', 'EUR', 'GBP'];
  static const _paymentMethods = <String>[
    'cash',
    'card',
    'upi',
    'bank_transfer',
    'paid_previously',
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
  List<BillLineItem> _receiptItems = const [];
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
    } else {
      final initialCategory = widget.initialCategory?.trim();
      final initialDescription = widget.initialDescription?.trim();
      final initialAmount = widget.initialAmount;
      final initialCurrency = widget.initialCurrency?.trim();
      final initialPaymentMethod = widget.initialPaymentMethod?.trim();
      if (initialDescription != null && initialDescription.isNotEmpty) {
        _descriptionController.text = initialDescription;
      }
      if (initialCategory != null && initialCategory.isNotEmpty) {
        _category = _normalizedChoice(initialCategory, _categories, 'Personal');
      }
      if (initialAmount != null && initialAmount > 0) {
        _amountController.text = initialAmount.toStringAsFixed(2);
      }
      if (initialCurrency != null && initialCurrency.isNotEmpty) {
        _currency = _normalizedChoice(initialCurrency, _currencies, 'INR');
      }
      if (initialPaymentMethod != null && initialPaymentMethod.isNotEmpty) {
        _paymentMethod = _normalizedChoice(
          initialPaymentMethod,
          _paymentMethods,
          'cash',
        );
      }
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
      final receiptItems = _receiptItems
          .where((item) => item.name.trim().isNotEmpty)
          .map((item) => item.toJson())
          .toList(growable: false);
      if (_editing) {
        bloc.add(UpdateExpense(expense: expense, receiptItems: receiptItems));
      } else {
        bloc.add(CreateExpense(expense: expense, receiptItems: receiptItems));
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
          _receiptItems = const [];
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
        _receiptItems = result.lineItems;
        if (result.dateExtracted) {
          _expenseDate = result.date;
        }
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
    final title = _editing ? 'Edit expense' : 'Add expense';
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: AppPageContainer(
        maxWidth: 700,
        children: [
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _billResult == null ? 'Choose how to add' : 'Review expense',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _billResult == null
                      ? 'Scan or upload a receipt, or enter the details manually.'
                      : 'Extracted fields stay editable before saving.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                _ExpenseChooserPanel(
                  extracting: _extractingBill,
                  saving: _saving,
                  onScanReceipt: _uploadBill,
                  onUploadReceipt: _uploadBill,
                ),
                if (_billMessage != null) ...[
                  const SizedBox(height: 12),
                  _AiStatusBanner(
                    message: _billMessage!,
                    extracting: _extractingBill,
                  ),
                ],
                if (_billResult != null) ...[
                  const SizedBox(height: 12),
                  _BillReviewPanel(
                    result: _billResult!,
                    items: _receiptItems,
                    currency: _currency,
                    onItemsChanged: (items) =>
                        setState(() => _receiptItems = items),
                  ),
                ],
                const SizedBox(height: 18),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'e.g. Rema 1000, Spotify, bus pass',
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
                if (_paymentMethod == 'paid_previously') ...[
                  const SizedBox(height: 8),
                  const _PaidPreviouslyNotice(),
                ],
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
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Row(
            children: [
              if (!_editing) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(addAnother: true),
                    icon: const Icon(Icons.add),
                    label: const Text('Save and add another'),
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
                    _BillReviewPanel(
                      result: _billResult!,
                      items: _receiptItems,
                      currency: _currency,
                      onItemsChanged: (items) =>
                          setState(() => _receiptItems = items),
                    ),
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
                      if (_paymentMethod == 'paid_previously')
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: _PaidPreviouslyNotice(),
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
      'paid_previously' => 'Paid previously',
      _ => 'Other',
    };
  }
}

class _ExpenseChooserPanel extends StatelessWidget {
  const _ExpenseChooserPanel({
    required this.extracting,
    required this.saving,
    required this.onScanReceipt,
    required this.onUploadReceipt,
  });

  final bool extracting;
  final bool saving;
  final VoidCallback onScanReceipt;
  final VoidCallback onUploadReceipt;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ChooserOption(
          title: extracting ? 'Reading receipt' : 'Scan receipt',
          subtitle: 'Camera or photo - AI reads merchant, items, and totals',
          icon: extracting ? Icons.hourglass_top : Icons.document_scanner,
          emphasized: true,
          enabled: !saving && !extracting,
          onTap: onScanReceipt,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ChooserOption(
                title: 'Upload receipt',
                subtitle: 'Photo from your device',
                icon: Icons.upload_file_outlined,
                enabled: !saving && !extracting,
                compact: true,
                onTap: onUploadReceipt,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: _ChooserOption(
                title: 'Enter manually',
                subtitle: 'Type the fields below',
                icon: Icons.edit_outlined,
                compact: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChooserOption extends StatelessWidget {
  const _ChooserOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.emphasized = false,
    this.enabled = true,
    this.compact = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool emphasized;
  final bool enabled;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = emphasized ? AppMoney.positiveColor : colors.primary;
    return Material(
      color: emphasized
          ? AppMoney.positiveColor.withValues(alpha: 0.06)
          : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: emphasized
              ? AppMoney.positiveColor.withValues(alpha: 0.28)
              : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SizedBox.square(
                  dimension: compact ? 38 : 44,
                  child: Icon(icon, color: accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiStatusBanner extends StatelessWidget {
  const _AiStatusBanner({required this.message, required this.extracting});

  final String message;
  final bool extracting;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppMoney.positiveColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppMoney.positiveColor.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (extracting)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.auto_awesome_outlined,
                size: 16,
                color: AppMoney.positiveColor,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppMoney.positiveColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaidPreviouslyNotice extends StatelessWidget {
  const _PaidPreviouslyNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.history_toggle_off_outlined,
              size: 18,
              color: colors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Counts toward this month without treating it as a new cash, card, or bank payment.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
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
  const _BillReviewPanel({
    required this.result,
    required this.items,
    required this.currency,
    required this.onItemsChanged,
  });

  final BillExtractionResult result;
  final List<BillLineItem> items;
  final String currency;
  final ValueChanged<List<BillLineItem>> onItemsChanged;

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
            const SizedBox(height: 8),
            Text(
              result.dateExtracted
                  ? 'Receipt date applied: ${DateFormatter.formatDate(result.date)}'
                  : 'No receipt date found. Date field stays editable.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ReceiptLineItemsReview(
              items: items,
              currency: currency,
              onChanged: onItemsChanged,
            ),
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
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: values
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                labelFor?.call(item) ?? item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
