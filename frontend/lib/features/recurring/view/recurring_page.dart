import 'dart:math' as math;

import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/features/recurring/models/recurring_template.dart';
import 'package:expense_tracker/features/recurring/repositories/api_recurring_repository.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class RecurringPage extends StatefulWidget {
  const RecurringPage({this.repository, super.key});

  final ApiRecurringRepository? repository;

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  late final ApiRecurringRepository _repository;
  http.Client? _client;
  var _templates = <RecurringTemplate>[];
  var _occurrences = <RecurringOccurrence>[];
  var _loading = true;
  var _saving = false;
  String? _error;
  late String _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = _monthKey(now);
    if (widget.repository == null) {
      _client = http.Client();
      _repository = ApiRecurringRepository(client: _client!);
    } else {
      _repository = widget.repository!;
    }
    _load();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repository.fetchTemplates(),
        _repository.fetchOccurrences(month: _month),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<RecurringTemplate>;
        _occurrences = results[1] as List<RecurringOccurrence>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _showCreateDialog() async {
    final draft = await showDialog<_RecurringDraft>(
      context: context,
      builder: (context) => const _CreateRecurringDialog(),
    );
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final startDay = math.min(draft.dayOfMonth, _lastDayOfMonth(now));
      await _repository.createTemplate(
        title: draft.title,
        kind: draft.kind,
        amount: draft.amount,
        category: draft.category,
        currency: 'INR',
        frequency: 'monthly',
        dayOfMonth: draft.dayOfMonth,
        startDate: DateTime(now.year, now.month, startDay),
      );
      await _load();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _confirmOccurrence(RecurringOccurrence occurrence) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => _ConfirmActualDialog(occurrence: occurrence),
    );
    if (amount == null) return;
    setState(() => _saving = true);
    try {
      await _repository.confirmOccurrence(
        occurrenceId: occurrence.id,
        actualAmount: amount,
        actualDate: DateTime.now(),
      );
      await _load();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final expectedIncome = _occurrences
        .where((item) => item.isIncome)
        .fold<double>(0, (sum, item) => sum + item.expectedAmount);
    final expectedPayments = _occurrences
        .where((item) => !item.isIncome)
        .fold<double>(0, (sum, item) => sum + item.expectedAmount);
    final confirmedIncome = _occurrences
        .where((item) => item.isIncome && item.isConfirmed)
        .fold<double>(0, (sum, item) => sum + (item.actualAmount ?? 0));
    final confirmedPayments = _occurrences
        .where((item) => !item.isIncome && item.isConfirmed)
        .fold<double>(0, (sum, item) => sum + (item.actualAmount ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            AppPageContainer(
              onRefresh: _load,
              children: [
                AppEmptyState(title: 'Recurring unavailable', subtitle: _error),
              ],
            )
          else
            AppPageContainer(
              onRefresh: _load,
              children: [
                _CashflowSummaryCard(
                  month: _monthTitle(_month),
                  expectedIncome: expectedIncome,
                  expectedPayments: expectedPayments,
                  confirmedIncome: confirmedIncome,
                  confirmedPayments: confirmedPayments,
                  onAdd: _showCreateDialog,
                ),
                const SizedBox(height: 16),
                const AppSectionHeader(title: 'This month'),
                if (_occurrences.isEmpty)
                  const AppEmptyState(
                    title: 'No recurring cashflow yet',
                    subtitle: 'Add salary, rent, subscriptions, or EMIs.',
                  )
                else
                  ..._occurrences.map(
                    (item) => _OccurrenceCard(
                      occurrence: item,
                      onConfirm: () => _confirmOccurrence(item),
                    ),
                  ),
                const SizedBox(height: 16),
                const AppSectionHeader(title: 'Rules'),
                if (_templates.isEmpty)
                  const AppEmptyState(
                    title: 'No rules saved',
                    subtitle: 'Monthly rules create expected items here.',
                  )
                else
                  ..._templates.map(_TemplateTile.new),
                const SizedBox(height: 88),
              ],
            ),
          if (_saving)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.08),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _showCreateDialog,
        icon: const Icon(Icons.event_repeat),
        label: const Text('Add recurring'),
      ),
    );
  }
}

class _CashflowSummaryCard extends StatelessWidget {
  const _CashflowSummaryCard({
    required this.month,
    required this.expectedIncome,
    required this.expectedPayments,
    required this.confirmedIncome,
    required this.confirmedPayments,
    required this.onAdd,
  });

  final String month;
  final double expectedIncome;
  final double expectedPayments;
  final double confirmedIncome;
  final double confirmedPayments;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final expectedLeft = expectedIncome - expectedPayments;
    final actualLeft = confirmedIncome - confirmedPayments;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  month,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Add recurring',
                onPressed: onAdd,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricPill(
                label: 'Expected left',
                value: AppMoney.format(expectedLeft),
                positive: expectedLeft >= 0,
              ),
              _MetricPill(
                label: 'Confirmed left',
                value: AppMoney.format(actualLeft),
                positive: actualLeft >= 0,
              ),
              _MetricPill(
                label: 'Income',
                value: AppMoney.format(expectedIncome),
                positive: true,
              ),
              _MetricPill(
                label: 'Payments',
                value: AppMoney.format(expectedPayments),
                positive: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.positive,
  });

  final String label;
  final String value;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = AppMoney.statusColor(context, positive: positive);
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _OccurrenceCard extends StatelessWidget {
  const _OccurrenceCard({required this.occurrence, required this.onConfirm});

  final RecurringOccurrence occurrence;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final color = occurrence.isIncome
        ? AppMoney.positiveColor
        : Theme.of(context).colorScheme.error;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(
              occurrence.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  occurrence.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${occurrence.category} • due ${_shortDate(occurrence.dueDate)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Expected ${AppMoney.format(occurrence.expectedAmount)}',
                    ),
                    if (occurrence.actualAmount != null)
                      Text(
                        'Actual ${AppMoney.format(occurrence.actualAmount!)}',
                      ),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        occurrence.isConfirmed ? 'Confirmed' : 'Expected',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onConfirm,
            child: Text(occurrence.isConfirmed ? 'Edit' : 'Confirm'),
          ),
        ],
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile(this.template);

  final RecurringTemplate template;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        template.kind == 'income'
            ? Icons.account_balance_wallet_outlined
            : Icons.event_repeat,
      ),
      title: Text(template.title),
      subtitle: Text('Every month on day ${template.dayOfMonth}'),
      trailing: Text(AppMoney.format(template.amount)),
    );
  }
}

class _CreateRecurringDialog extends StatefulWidget {
  const _CreateRecurringDialog();

  @override
  State<_CreateRecurringDialog> createState() => _CreateRecurringDialogState();
}

class _CreateRecurringDialogState extends State<_CreateRecurringDialog> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _dayController = TextEditingController(text: '15');
  final _categoryController = TextEditingController(text: 'Salary');
  var _kind = 'income';
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _dayController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final day = int.tryParse(_dayController.text.trim()) ?? 0;
    final category = _categoryController.text.trim();
    if (title.isEmpty || amount <= 0 || day < 1 || day > 31) {
      setState(() {
        _error = 'Add a title, valid amount, and day between 1 and 31.';
      });
      return;
    }
    Navigator.of(context).pop(
      _RecurringDraft(
        title: title,
        kind: _kind,
        amount: amount,
        category: category.isEmpty
            ? (_kind == 'income' ? 'Salary' : 'Bills')
            : category,
        dayOfMonth: day,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add recurring'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'income',
                  label: Text('Income'),
                  icon: Icon(Icons.arrow_downward),
                ),
                ButtonSegment(
                  value: 'expense',
                  label: Text('Payment'),
                  icon: Icon(Icons.arrow_upward),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (value) {
                setState(() {
                  _kind = value.first;
                  if (_categoryController.text.trim().isEmpty ||
                      _categoryController.text == 'Salary' ||
                      _categoryController.text == 'Bills') {
                    _categoryController.text = _kind == 'income'
                        ? 'Salary'
                        : 'Bills';
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Salary, rent, EMI',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Expected amount',
                prefixText: AppMoney.inputPrefix,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dayController,
              decoration: const InputDecoration(labelText: 'Day of month'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: 'Category'),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _ConfirmActualDialog extends StatefulWidget {
  const _ConfirmActualDialog({required this.occurrence});

  final RecurringOccurrence occurrence;

  @override
  State<_ConfirmActualDialog> createState() => _ConfirmActualDialogState();
}

class _ConfirmActualDialogState extends State<_ConfirmActualDialog> {
  late final TextEditingController _amountController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: (widget.occurrence.actualAmount ?? widget.occurrence.expectedAmount)
          .toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Enter the actual amount received or paid.');
      return;
    }
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.occurrence.isConfirmed ? 'Edit actual' : 'Confirm actual',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.occurrence.title),
          const SizedBox(height: 8),
          Text('Expected ${AppMoney.format(widget.occurrence.expectedAmount)}'),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Actual amount',
              prefixText: AppMoney.inputPrefix,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _RecurringDraft {
  const _RecurringDraft({
    required this.title,
    required this.kind,
    required this.amount,
    required this.category,
    required this.dayOfMonth,
  });

  final String title;
  final String kind;
  final double amount;
  final String category;
  final int dayOfMonth;
}

String _monthKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
}

String _monthTitle(String month) {
  const names = [
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
  final parts = month.split('-');
  final monthNumber = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
  final year = parts.isNotEmpty ? parts.first : '';
  return '${names[(monthNumber - 1).clamp(0, 11)]} $year';
}

String _shortDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}

int _lastDayOfMonth(DateTime date) {
  return DateTime(date.year, date.month + 1, 0).day;
}
