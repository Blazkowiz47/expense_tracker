import 'dart:async';

import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/utils/date_formatter.dart';
import 'package:expense_tracker/data/repositories/freshness_repository.dart';
import 'package:expense_tracker/features/savings/models/savings_goal.dart';
import 'package:expense_tracker/features/savings/repositories/api_savings_repository.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _savingsCurrencyOptions = <String>['NOK', 'INR', 'USD', 'EUR', 'GBP'];

class SavingsPage extends StatefulWidget {
  const SavingsPage({
    this.repository,
    this.freshnessRepository,
    this.autoRefresh = false,
    super.key,
  });

  final ApiSavingsRepository? repository;
  final FreshnessRepository? freshnessRepository;
  final bool autoRefresh;

  @override
  State<SavingsPage> createState() => _SavingsPageState();
}

class _SavingsPageState extends State<SavingsPage> {
  late final ApiSavingsRepository _repository;
  late final FreshnessRepository _freshnessRepository;
  late final bool _ownsFreshnessRepository;
  http.Client? _client;
  var _goals = <SavingsGoal>[];
  var _loading = true;
  var _loadedSavings = false;
  var _saving = false;
  String? _busyGoalId;
  String? _error;
  DateTime? _savingsFreshnessCursor;

  @override
  void initState() {
    super.initState();
    if (widget.repository == null) {
      _client = http.Client();
      _repository = ApiSavingsRepository(client: _client!);
    } else {
      _repository = widget.repository!;
    }
    _freshnessRepository =
        widget.freshnessRepository ?? FreshnessRepository(client: _client);
    _ownsFreshnessRepository = widget.freshnessRepository == null;
    _loadGoals();
  }

  @override
  void dispose() {
    if (_ownsFreshnessRepository) {
      _freshnessRepository.dispose();
    }
    _client?.close();
    super.dispose();
  }

  Future<void> _loadGoals({
    bool showLoading = true,
    bool markFreshness = true,
  }) async {
    setState(() {
      _loading = showLoading || _goals.isEmpty;
      _error = null;
    });
    try {
      final goals = await _repository.fetchGoals();
      if (!mounted) return;
      setState(() {
        _goals = goals;
        _loading = false;
        _loadedSavings = true;
      });
      if (markFreshness) {
        unawaited(_markSavingsFreshnessSeen());
      }
    } catch (error) {
      if (!mounted) return;
      if (!showLoading && _goals.isNotEmpty) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _autoRefreshSavings() async {
    final freshness = await _freshnessRepository.fetchFreshness(
      since: _savingsFreshnessCursor,
      sections: const ['savings'],
    );
    final savings = freshness.sections['savings'];
    if (savings != null && !savings.changed && _loadedSavings) {
      _savingsFreshnessCursor = freshness.serverTime;
      return;
    }
    await _loadGoals(showLoading: false, markFreshness: false);
    _savingsFreshnessCursor = freshness.serverTime;
  }

  Future<void> _markSavingsFreshnessSeen() async {
    try {
      final freshness = await _freshnessRepository.fetchFreshness(
        sections: const ['savings'],
      );
      _savingsFreshnessCursor = freshness.serverTime;
    } catch (_) {}
  }

  Future<void> _openGoalDialog({SavingsGoal? goal}) async {
    final draft = await showDialog<_SavingsGoalDraft>(
      context: context,
      builder: (context) => _SavingsGoalDialog(goal: goal),
    );
    if (draft == null) return;
    await _runSavingsAction(
      busyGoalId: goal?.id,
      failureMessage: goal == null
          ? 'Could not add this savings goal. Refreshed latest data.'
          : 'Could not update this savings goal. Refreshed latest data.',
      action: () async {
        if (goal == null) {
          await _repository.createGoal(
            name: draft.name,
            targetAmount: draft.targetAmount,
            targetCurrency: draft.targetCurrency,
            sourceCurrency: draft.sourceCurrency,
            monthlyTargetAmount: draft.monthlyTargetAmount,
            startMonth: draft.startMonth,
            notes: draft.notes,
          );
        } else {
          await _repository.updateGoal(
            id: goal.id,
            name: draft.name,
            targetAmount: draft.targetAmount,
            targetCurrency: draft.targetCurrency,
            sourceCurrency: draft.sourceCurrency,
            monthlyTargetAmount: draft.monthlyTargetAmount,
            startMonth: draft.startMonth,
            notes: draft.notes,
          );
        }
      },
    );
  }

  Future<void> _logContribution(SavingsGoal goal) async {
    final draft = await showDialog<_SavingsContributionDraft>(
      context: context,
      builder: (context) => _SavingsContributionDialog(goal: goal),
    );
    if (draft == null) return;
    await _runSavingsAction(
      busyGoalId: goal.id,
      successMessage: 'Saving logged.',
      failureMessage: 'Could not log this saving. Refreshed latest data.',
      action: () async {
        await _repository.addContribution(
          goalId: goal.id,
          sourceAmount: draft.sourceAmount,
          sourceCurrency: draft.sourceCurrency,
          targetAmount: draft.targetAmount,
          feeAmount: draft.feeAmount,
          feeCurrency: draft.feeCurrency,
          date: draft.date,
          notes: draft.notes,
        );
      },
    );
  }

  Future<void> _archiveGoal(SavingsGoal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive goal?'),
        content: Text(goal.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runSavingsAction(
      busyGoalId: goal.id,
      failureMessage: 'Could not archive this savings goal.',
      action: () async {
        await _repository.archiveGoal(goal.id);
      },
    );
  }

  Future<void> _runSavingsAction({
    required Future<void> Function() action,
    required String failureMessage,
    String? successMessage,
    String? busyGoalId,
  }) async {
    setState(() {
      _saving = true;
      _busyGoalId = busyGoalId;
    });
    try {
      await action();
      await _loadGoals();
      if (mounted && successMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failureMessage)));
        await _loadGoals(showLoading: false);
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _busyGoalId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeGoals = _goals.where((goal) => !goal.archived).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadGoals,
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
              onRefresh: () => _loadGoals(showLoading: false),
              onAutoRefresh: _autoRefreshSavings,
              autoRefresh: widget.autoRefresh,
              children: [
                AppEmptyState(title: 'Savings unavailable', subtitle: _error),
              ],
            )
          else
            AppPageContainer(
              onRefresh: () => _loadGoals(showLoading: false),
              onAutoRefresh: _autoRefreshSavings,
              autoRefresh: widget.autoRefresh,
              children: [
                _SavingsSummaryCard(
                  goals: activeGoals,
                  onAdd: () => _openGoalDialog(),
                ),
                const SizedBox(height: 16),
                AppSectionHeader(
                  title: 'Goals',
                  actionLabel: 'Add',
                  onAction: () => _openGoalDialog(),
                ),
                if (activeGoals.isEmpty)
                  AppEmptyState(
                    title: 'No savings goals',
                    actionLabel: 'Add goal',
                    onAction: () => _openGoalDialog(),
                  )
                else
                  ...activeGoals.map(
                    (goal) => _SavingsGoalCard(
                      goal: goal,
                      busy: _busyGoalId == goal.id,
                      onLogContribution: () => _logContribution(goal),
                      onEdit: () => _openGoalDialog(goal: goal),
                      onArchive: () => _archiveGoal(goal),
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
        onPressed: _saving ? null : () => _openGoalDialog(),
        icon: const Icon(Icons.savings_outlined),
        label: const Text('Add goal'),
      ),
    );
  }
}

class _SavingsSummaryCard extends StatelessWidget {
  const _SavingsSummaryCard({required this.goals, required this.onAdd});

  final List<SavingsGoal> goals;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final saved = _sumByTargetCurrency(goals, (goal) => goal.totalSavedAmount);
    final monthly = _sumByTargetCurrency(
      goals,
      (goal) => goal.monthlyTargetAmount,
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
                  'Savings goals',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Add goal',
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
              _SavingsMetricPill(
                label: 'Active',
                value: goals.length.toString(),
                icon: Icons.flag_outlined,
              ),
              _SavingsMetricPill(
                label: 'Saved',
                value: AppMoney.formatCurrencyAmounts(saved),
                icon: Icons.savings_outlined,
              ),
              _SavingsMetricPill(
                label: 'Monthly target',
                value: AppMoney.formatCurrencyAmounts(monthly),
                icon: Icons.calendar_month_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavingsMetricPill extends StatelessWidget {
  const _SavingsMetricPill({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 174,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SavingsGoalCard extends StatelessWidget {
  const _SavingsGoalCard({
    required this.goal,
    required this.busy,
    required this.onLogContribution,
    required this.onEdit,
    required this.onArchive,
  });

  final SavingsGoal goal;
  final bool busy;
  final VoidCallback onLogContribution;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: colors.tertiaryContainer,
                child: Icon(
                  Icons.savings_outlined,
                  color: colors.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${goal.sourceCurrency} -> ${goal.targetCurrency}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_SavingsAction>(
                tooltip: 'Goal actions',
                icon: const Icon(Icons.more_vert),
                onSelected: (action) {
                  switch (action) {
                    case _SavingsAction.edit:
                      onEdit();
                    case _SavingsAction.archive:
                      onArchive();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _SavingsAction.edit,
                    child: _SavingsActionRow(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                    ),
                  ),
                  PopupMenuItem(
                    value: _SavingsAction.archive,
                    child: _SavingsActionRow(
                      icon: Icons.archive_outlined,
                      label: 'Archive',
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppProgressBar(
            value: goal.progress,
            color: goal.progress >= 1 ? AppMoney.positiveColor : colors.primary,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SavingsInfoChip(
                label: 'Saved',
                value: AppMoney.formatCurrency(
                  goal.totalSavedAmount,
                  goal.targetCurrency,
                ),
              ),
              _SavingsInfoChip(
                label: 'Target',
                value: AppMoney.formatCurrency(
                  goal.targetAmount,
                  goal.targetCurrency,
                ),
              ),
              _SavingsInfoChip(
                label: 'Remaining',
                value: AppMoney.formatCurrency(
                  goal.remainingAmount,
                  goal.targetCurrency,
                ),
              ),
              if (goal.monthlyTargetAmount > 0)
                _SavingsInfoChip(
                  label: 'This month',
                  value:
                      '${AppMoney.formatCurrency(goal.currentMonthSavedAmount, goal.targetCurrency)} / ${AppMoney.formatCurrency(goal.monthlyTargetAmount, goal.targetCurrency)}',
                ),
            ],
          ),
          if (goal.lastContributionAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last saved ${DateFormatter.formatDate(goal.lastContributionAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: busy ? null : onLogContribution,
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('Log saving'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavingsInfoChip extends StatelessWidget {
  const _SavingsInfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label: $value'),
    );
  }
}

enum _SavingsAction { edit, archive }

class _SavingsActionRow extends StatelessWidget {
  const _SavingsActionRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}

class _SavingsGoalDialog extends StatefulWidget {
  const _SavingsGoalDialog({this.goal});

  final SavingsGoal? goal;

  @override
  State<_SavingsGoalDialog> createState() => _SavingsGoalDialogState();
}

class _SavingsGoalDialogState extends State<_SavingsGoalDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _targetController;
  late final TextEditingController _monthlyController;
  late final TextEditingController _startMonthController;
  late final TextEditingController _notesController;
  var _sourceCurrency = 'NOK';
  var _targetCurrency = 'INR';
  String? _error;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    _sourceCurrency = goal?.sourceCurrency ?? 'NOK';
    _targetCurrency = goal?.targetCurrency ?? 'INR';
    _nameController = TextEditingController(
      text: goal?.name ?? 'India savings',
    );
    _targetController = TextEditingController(
      text: goal == null ? '' : goal.targetAmount.toStringAsFixed(0),
    );
    _monthlyController = TextEditingController(
      text: goal == null || goal.monthlyTargetAmount == 0
          ? ''
          : goal.monthlyTargetAmount.toStringAsFixed(0),
    );
    _startMonthController = TextEditingController(
      text: goal?.startMonth ?? _monthKey(DateTime.now()),
    );
    _notesController = TextEditingController(text: goal?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _monthlyController.dispose();
    _startMonthController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final target = double.tryParse(_targetController.text.trim()) ?? 0;
    final monthly = double.tryParse(_monthlyController.text.trim()) ?? 0;
    final startMonth = _startMonthController.text.trim();
    if (name.isEmpty ||
        target <= 0 ||
        monthly < 0 ||
        !_isMonthKey(startMonth)) {
      setState(() {
        _error = 'Add a name, positive target, and month as YYYY-MM.';
      });
      return;
    }
    Navigator.of(context).pop(
      _SavingsGoalDraft(
        name: name,
        targetAmount: target,
        targetCurrency: _targetCurrency,
        sourceCurrency: _sourceCurrency,
        monthlyTargetAmount: monthly,
        startMonth: startMonth,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.goal != null;
    return AlertDialog(
      title: Text(editing ? 'Edit goal' : 'Add goal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _sourceCurrency,
                    decoration: const InputDecoration(
                      labelText: 'From',
                      border: OutlineInputBorder(),
                    ),
                    items: _savingsCurrencyOptions
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _sourceCurrency = value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _targetCurrency,
                    decoration: const InputDecoration(
                      labelText: 'To',
                      border: OutlineInputBorder(),
                    ),
                    items: _savingsCurrencyOptions
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _targetCurrency = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetController,
              decoration: InputDecoration(
                labelText: 'Target',
                prefixText: '$_targetCurrency ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _monthlyController,
              decoration: InputDecoration(
                labelText: 'Monthly target',
                prefixText: '$_targetCurrency ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _startMonthController,
              decoration: const InputDecoration(labelText: 'Start month'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              minLines: 1,
              maxLines: 3,
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

class _SavingsContributionDialog extends StatefulWidget {
  const _SavingsContributionDialog({required this.goal});

  final SavingsGoal goal;

  @override
  State<_SavingsContributionDialog> createState() =>
      _SavingsContributionDialogState();
}

class _SavingsContributionDialogState
    extends State<_SavingsContributionDialog> {
  late final TextEditingController _sourceController;
  late final TextEditingController _targetController;
  late final TextEditingController _feeController;
  late final TextEditingController _notesController;
  late DateTime _date;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _sourceController = TextEditingController();
    _targetController = TextEditingController();
    _feeController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _targetController.dispose();
    _feeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  void _submit() {
    final source = double.tryParse(_sourceController.text.trim()) ?? 0;
    final targetText = _targetController.text.trim();
    final target = targetText.isEmpty ? null : double.tryParse(targetText);
    final fee = double.tryParse(_feeController.text.trim()) ?? 0;
    if (source <= 0 || fee < 0 || (targetText.isNotEmpty && target == null)) {
      setState(() {
        _error = 'Add a positive source amount and valid received amount.';
      });
      return;
    }
    Navigator.of(context).pop(
      _SavingsContributionDraft(
        sourceAmount: source,
        sourceCurrency: widget.goal.sourceCurrency,
        targetAmount: target,
        feeAmount: fee,
        feeCurrency: widget.goal.sourceCurrency,
        date: _date,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log saving'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _sourceController,
              decoration: InputDecoration(
                labelText: 'Sent',
                prefixText: '${widget.goal.sourceCurrency} ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetController,
              decoration: InputDecoration(
                labelText: 'Received',
                prefixText: '${widget.goal.targetCurrency} ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _feeController,
              decoration: InputDecoration(
                labelText: 'Fee',
                prefixText: '${widget.goal.sourceCurrency} ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(DateFormatter.formatDate(_date)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
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

class _SavingsGoalDraft {
  const _SavingsGoalDraft({
    required this.name,
    required this.targetAmount,
    required this.targetCurrency,
    required this.sourceCurrency,
    required this.monthlyTargetAmount,
    required this.startMonth,
    required this.notes,
  });

  final String name;
  final double targetAmount;
  final String targetCurrency;
  final String sourceCurrency;
  final double monthlyTargetAmount;
  final String startMonth;
  final String notes;
}

class _SavingsContributionDraft {
  const _SavingsContributionDraft({
    required this.sourceAmount,
    required this.sourceCurrency,
    required this.targetAmount,
    required this.feeAmount,
    required this.feeCurrency,
    required this.date,
    required this.notes,
  });

  final double sourceAmount;
  final String sourceCurrency;
  final double? targetAmount;
  final double feeAmount;
  final String feeCurrency;
  final DateTime date;
  final String notes;
}

Map<String, num> _sumByTargetCurrency(
  Iterable<SavingsGoal> goals,
  double Function(SavingsGoal goal) valueForGoal,
) {
  final amounts = <String, num>{};
  for (final goal in goals) {
    final amount = valueForGoal(goal);
    if (amount.abs() <= 0.005) continue;
    amounts[goal.targetCurrency] = (amounts[goal.targetCurrency] ?? 0) + amount;
  }
  return amounts;
}

String _monthKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
}

bool _isMonthKey(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final month = int.tryParse(match.group(2) ?? '') ?? 0;
  return month >= 1 && month <= 12;
}
