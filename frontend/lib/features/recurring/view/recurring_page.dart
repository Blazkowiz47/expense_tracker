import 'dart:async';
import 'dart:math' as math;

import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/data/repositories/freshness_repository.dart';
import 'package:expense_tracker/features/recurring/models/recurring_template.dart';
import 'package:expense_tracker/features/recurring/repositories/api_recurring_repository.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _recurringCurrencyOptions = <String>['INR', 'USD', 'EUR', 'GBP', 'NOK'];
const _recurringFrequencyOptions = <String>['monthly', 'weekly', 'daily'];

class RecurringPage extends StatefulWidget {
  const RecurringPage({
    this.repository,
    this.freshnessRepository,
    this.initialMonth,
    this.initialOccurrenceId,
    this.openConfirmOnLaunch = false,
    this.autoRefresh = false,
    super.key,
  });

  final ApiRecurringRepository? repository;
  final FreshnessRepository? freshnessRepository;
  final String? initialMonth;
  final String? initialOccurrenceId;
  final bool openConfirmOnLaunch;
  final bool autoRefresh;

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  late final ApiRecurringRepository _repository;
  late final FreshnessRepository _freshnessRepository;
  late final bool _ownsFreshnessRepository;
  http.Client? _client;
  var _templates = <RecurringTemplate>[];
  var _occurrences = <RecurringOccurrence>[];
  var _loading = true;
  var _loadedRecurring = false;
  var _saving = false;
  var _didOpenInitialOccurrence = false;
  String? _error;
  late String _month;
  DateTime? _recurringFreshnessCursor;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = _validMonthKey(widget.initialMonth) ?? _monthKey(now);
    if (widget.repository == null) {
      _client = http.Client();
      _repository = ApiRecurringRepository(client: _client!);
    } else {
      _repository = widget.repository!;
    }
    _freshnessRepository =
        widget.freshnessRepository ?? FreshnessRepository(client: _client);
    _ownsFreshnessRepository = widget.freshnessRepository == null;
    _load();
  }

  @override
  void dispose() {
    if (_ownsFreshnessRepository) {
      _freshnessRepository.dispose();
    }
    _client?.close();
    super.dispose();
  }

  Future<void> _load({
    bool showLoading = true,
    bool markFreshness = true,
  }) async {
    setState(() {
      _loading = showLoading || (_templates.isEmpty && _occurrences.isEmpty);
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
        _loadedRecurring = true;
      });
      if (markFreshness) {
        unawaited(_markRecurringFreshnessSeen());
      }
      _openInitialOccurrenceAction();
    } catch (error) {
      if (!mounted) return;
      if (!showLoading && (_templates.isNotEmpty || _occurrences.isNotEmpty)) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _openInitialOccurrenceAction() {
    if (_didOpenInitialOccurrence || !widget.openConfirmOnLaunch) return;
    final occurrenceId = widget.initialOccurrenceId?.trim();
    if (occurrenceId == null || occurrenceId.isEmpty) return;
    RecurringOccurrence? target;
    for (final occurrence in _occurrences) {
      if (occurrence.id == occurrenceId) {
        target = occurrence;
        break;
      }
    }
    if (target == null) return;
    _didOpenInitialOccurrence = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _confirmOccurrence(target!);
    });
  }

  Future<void> _autoRefreshRecurring() async {
    final freshness = await _freshnessRepository.fetchFreshness(
      since: _recurringFreshnessCursor,
      sections: const ['recurring'],
    );
    final recurring = freshness.sections['recurring'];
    if (recurring != null && !recurring.changed && _loadedRecurring) {
      _recurringFreshnessCursor = freshness.serverTime;
      return;
    }
    await _load(showLoading: false, markFreshness: false);
    _recurringFreshnessCursor = freshness.serverTime;
  }

  Future<void> _markRecurringFreshnessSeen() async {
    try {
      final freshness = await _freshnessRepository.fetchFreshness(
        sections: const ['recurring'],
      );
      _recurringFreshnessCursor = freshness.serverTime;
    } catch (_) {}
  }

  Future<void> _showCreateDialog() async {
    final draft = await showDialog<_RecurringDraft>(
      context: context,
      builder: (context) => const _CreateRecurringDialog(),
    );
    if (draft == null) return;
    await _runRecurringAction(
      failureMessage:
          'Could not save this recurring rule. Refreshed latest data.',
      action: () async {
        final now = DateTime.now();
        final startDay = math.min(draft.dayOfMonth, _lastDayOfMonth(now));
        await _repository.createTemplate(
          title: draft.title,
          kind: draft.kind,
          amount: draft.amount,
          category: draft.category,
          currency: draft.currency,
          frequency: draft.frequency,
          dayOfMonth: draft.dayOfMonth,
          startDate: DateTime(now.year, now.month, startDay),
        );
      },
    );
  }

  Future<void> _showEditDialog(RecurringTemplate template) async {
    final draft = await showDialog<_RecurringDraft>(
      context: context,
      builder: (context) => _CreateRecurringDialog(template: template),
    );
    if (draft == null) return;
    await _runRecurringAction(
      failureMessage:
          'Could not update this recurring rule. Refreshed latest data.',
      action: () async {
        await _repository.updateTemplate(
          id: template.id,
          title: draft.title,
          kind: draft.kind,
          amount: draft.amount,
          category: draft.category,
          currency: draft.currency,
          frequency: draft.frequency,
          dayOfMonth: draft.dayOfMonth,
          startDate: template.startDate,
        );
      },
    );
  }

  Future<void> _toggleTemplateActive(RecurringTemplate template) async {
    await _runRecurringAction(
      failureMessage: template.active
          ? 'Could not pause this recurring rule. Refreshed latest data.'
          : 'Could not resume this recurring rule. Refreshed latest data.',
      action: () async {
        if (template.active) {
          await _repository.pauseTemplate(template.id);
        } else {
          await _repository.resumeTemplate(template.id);
        }
      },
    );
  }

  Future<void> _deleteTemplate(RecurringTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete rule?'),
        content: Text(
          'Delete ${template.title}? Confirmed history stays saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runRecurringAction(
      failureMessage:
          'Could not delete this recurring rule. Refreshed latest data.',
      action: () async {
        await _repository.deleteTemplate(template.id);
      },
    );
  }

  Future<void> _confirmOccurrence(RecurringOccurrence occurrence) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => _ConfirmActualDialog(occurrence: occurrence),
    );
    if (amount == null) return;
    await _runRecurringAction(
      failureMessage:
          'Could not confirm this recurring item. Refreshed latest data.',
      action: () async {
        await _repository.confirmOccurrence(
          occurrenceId: occurrence.id,
          actualAmount: amount,
          actualDate: DateTime.now(),
        );
      },
    );
  }

  Future<void> _runRecurringAction({
    required Future<void> Function() action,
    required String failureMessage,
  }) async {
    setState(() => _saving = true);
    try {
      await action();
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failureMessage)));
        await _load(showLoading: false);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final expectedIncome = _sumOccurrencesByCurrency(
      _occurrences.where((item) => item.isIncome),
      actual: false,
    );
    final expectedPayments = _sumOccurrencesByCurrency(
      _occurrences.where((item) => !item.isIncome),
      actual: false,
    );
    final confirmedIncome = _sumOccurrencesByCurrency(
      _occurrences.where((item) => item.isIncome && item.isConfirmed),
      actual: true,
    );
    final confirmedPayments = _sumOccurrencesByCurrency(
      _occurrences.where((item) => !item.isIncome && item.isConfirmed),
      actual: true,
    );

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
              onRefresh: () => _load(showLoading: false),
              onAutoRefresh: _autoRefreshRecurring,
              autoRefresh: widget.autoRefresh,
              children: [
                AppEmptyState(title: 'Recurring unavailable', subtitle: _error),
              ],
            )
          else
            AppPageContainer(
              onRefresh: () => _load(showLoading: false),
              onAutoRefresh: _autoRefreshRecurring,
              autoRefresh: widget.autoRefresh,
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
                  ..._templates.map(
                    (item) => _TemplateTile(
                      template: item,
                      onEdit: () => _showEditDialog(item),
                      onToggleActive: () => _toggleTemplateActive(item),
                      onDelete: () => _deleteTemplate(item),
                    ),
                  ),
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
  final Map<String, double> expectedIncome;
  final Map<String, double> expectedPayments;
  final Map<String, double> confirmedIncome;
  final Map<String, double> confirmedPayments;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final expectedLeft = _subtractCurrencyMaps(
      expectedIncome,
      expectedPayments,
    );
    final actualLeft = _subtractCurrencyMaps(
      confirmedIncome,
      confirmedPayments,
    );
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
                value: _formatCurrencyMap(expectedLeft),
                positive: _allNonNegative(expectedLeft),
              ),
              _MetricPill(
                label: 'Confirmed left',
                value: _formatCurrencyMap(actualLeft),
                positive: _allNonNegative(actualLeft),
              ),
              _MetricPill(
                label: 'Income',
                value: _formatCurrencyMap(expectedIncome),
                positive: true,
              ),
              _MetricPill(
                label: 'Payments',
                value: _formatCurrencyMap(expectedPayments),
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
                      'Expected ${AppMoney.formatCurrency(occurrence.expectedAmount, occurrence.currency)}',
                    ),
                    if (occurrence.actualAmount != null)
                      Text(
                        'Actual ${AppMoney.formatCurrency(occurrence.actualAmount!, occurrence.currency)}',
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
  const _TemplateTile({
    required this.template,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final RecurringTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onEdit,
      leading: Icon(
        template.kind == 'income'
            ? Icons.account_balance_wallet_outlined
            : Icons.event_repeat,
      ),
      title: Text(template.title),
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${_frequencyLabel(template.frequency)} · day ${template.dayOfMonth}',
          ),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(template.active ? 'Active' : 'Paused'),
          ),
        ],
      ),
      trailing: SizedBox(
        width: 168,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                AppMoney.formatCurrency(template.amount, template.currency),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
            PopupMenuButton<_TemplateAction>(
              tooltip: 'Rule actions',
              icon: const Icon(Icons.more_vert),
              onSelected: (action) {
                switch (action) {
                  case _TemplateAction.edit:
                    onEdit();
                  case _TemplateAction.toggleActive:
                    onToggleActive();
                  case _TemplateAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _TemplateAction.edit,
                  child: _TemplateActionRow(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                  ),
                ),
                PopupMenuItem(
                  value: _TemplateAction.toggleActive,
                  child: _TemplateActionRow(
                    icon: template.active
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    label: template.active ? 'Pause' : 'Resume',
                  ),
                ),
                const PopupMenuItem(
                  value: _TemplateAction.delete,
                  child: _TemplateActionRow(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _TemplateAction { edit, toggleActive, delete }

class _TemplateActionRow extends StatelessWidget {
  const _TemplateActionRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}

class _CreateRecurringDialog extends StatefulWidget {
  const _CreateRecurringDialog({this.template});

  final RecurringTemplate? template;

  @override
  State<_CreateRecurringDialog> createState() => _CreateRecurringDialogState();
}

class _CreateRecurringDialogState extends State<_CreateRecurringDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _dayController;
  late final TextEditingController _categoryController;
  var _kind = 'income';
  var _currency = 'INR';
  var _frequency = 'monthly';
  String? _error;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    _kind = template?.kind ?? 'income';
    _currency = template?.currency ?? 'INR';
    _frequency = template?.frequency ?? 'monthly';
    _titleController = TextEditingController(text: template?.title ?? '');
    _amountController = TextEditingController(
      text: template == null ? '' : template.amount.toStringAsFixed(0),
    );
    _dayController = TextEditingController(
      text: (template?.dayOfMonth ?? 15).toString(),
    );
    _categoryController = TextEditingController(
      text: template?.category ?? 'Salary',
    );
  }

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
        currency: _currency,
        frequency: _frequency,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.template != null;
    return AlertDialog(
      title: Text(editing ? 'Edit recurring' : 'Add recurring'),
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
              decoration: InputDecoration(
                labelText: 'Expected amount',
                prefixText: '$_currency ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(
                labelText: 'Currency',
                border: OutlineInputBorder(),
              ),
              items: _recurringCurrencyOptions
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _currency = value);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(),
              ),
              items: _recurringFrequencyOptions
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(_frequencyLabel(item)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _frequency = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dayController,
              decoration: const InputDecoration(
                labelText: 'Start day of month',
              ),
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
          Text(
            'Expected ${AppMoney.formatCurrency(widget.occurrence.expectedAmount, widget.occurrence.currency)}',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Actual amount',
              prefixText: '${widget.occurrence.currency} ',
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
    required this.currency,
    required this.frequency,
  });

  final String title;
  final String kind;
  final double amount;
  final String category;
  final int dayOfMonth;
  final String currency;
  final String frequency;
}

String _monthKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
}

String? _validMonthKey(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split('-');
  if (parts.length != 2) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return null;
  return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
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

Map<String, double> _sumOccurrencesByCurrency(
  Iterable<RecurringOccurrence> occurrences, {
  required bool actual,
}) {
  final totals = <String, double>{};
  for (final occurrence in occurrences) {
    final amount = actual
        ? occurrence.actualAmount ?? 0
        : occurrence.expectedAmount;
    if (amount <= 0) continue;
    final currency = _normalizeCurrency(occurrence.currency);
    totals[currency] = (totals[currency] ?? 0) + amount;
  }
  return totals;
}

Map<String, double> _subtractCurrencyMaps(
  Map<String, double> left,
  Map<String, double> right,
) {
  final result = <String, double>{};
  for (final currency in {...left.keys, ...right.keys}) {
    result[currency] = (left[currency] ?? 0) - (right[currency] ?? 0);
  }
  result.removeWhere((currency, amount) => amount.abs() <= 0.005);
  return result;
}

bool _allNonNegative(Map<String, double> amounts) {
  if (amounts.isEmpty) return true;
  return amounts.values.every((amount) => amount >= -0.005);
}

String _formatCurrencyMap(Map<String, double> amounts) {
  final entries =
      amounts.entries.where((entry) => entry.value.abs() > 0.005).toList()
        ..sort((a, b) => a.key.compareTo(b.key));
  if (entries.isEmpty) {
    return AppMoney.format(0);
  }
  return entries
      .map((entry) => AppMoney.formatCurrency(entry.value, entry.key))
      .join(' / ');
}

String _frequencyLabel(String frequency) {
  return switch (frequency.trim().toLowerCase()) {
    'daily' => 'Daily',
    'weekly' => 'Weekly',
    _ => 'Monthly',
  };
}

String _normalizeCurrency(String value) {
  final currency = value.trim().toUpperCase();
  return RegExp(r'^[A-Z]{3}$').hasMatch(currency) ? currency : 'INR';
}

int _lastDayOfMonth(DateTime date) {
  return DateTime(date.year, date.month + 1, 0).day;
}
