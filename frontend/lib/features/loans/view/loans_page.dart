import 'dart:async';

import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/utils/date_formatter.dart';
import 'package:expense_tracker/data/repositories/freshness_repository.dart';
import 'package:expense_tracker/features/loans/models/loan.dart';
import 'package:expense_tracker/features/loans/repositories/api_loans_repository.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _loanCurrencyOptions = <String>['INR', 'USD', 'EUR', 'GBP', 'NOK'];
const _loanTypeOptions = <String>[
  'Personal',
  'Home',
  'Car',
  'Education',
  'Credit card',
  'Other',
];
const _loanRateTypeOptions = <String>['fixed', 'floating', 'unknown'];

class LoansPage extends StatefulWidget {
  const LoansPage({
    this.repository,
    this.freshnessRepository,
    this.autoRefresh = false,
    super.key,
  });

  final ApiLoansRepository? repository;
  final FreshnessRepository? freshnessRepository;
  final bool autoRefresh;

  @override
  State<LoansPage> createState() => _LoansPageState();
}

class _LoansPageState extends State<LoansPage> {
  late final ApiLoansRepository _repository;
  late final FreshnessRepository _freshnessRepository;
  late final bool _ownsFreshnessRepository;
  http.Client? _client;
  var _loans = <Loan>[];
  var _loading = true;
  var _loadedLoans = false;
  var _saving = false;
  String? _busyLoanId;
  String? _error;
  DateTime? _loansFreshnessCursor;

  @override
  void initState() {
    super.initState();
    if (widget.repository == null) {
      _client = http.Client();
      _repository = ApiLoansRepository(client: _client!);
    } else {
      _repository = widget.repository!;
    }
    _freshnessRepository =
        widget.freshnessRepository ?? FreshnessRepository(client: _client);
    _ownsFreshnessRepository = widget.freshnessRepository == null;
    _loadLoans();
  }

  @override
  void dispose() {
    if (_ownsFreshnessRepository) {
      _freshnessRepository.dispose();
    }
    _client?.close();
    super.dispose();
  }

  Future<void> _loadLoans({
    bool showLoading = true,
    bool markFreshness = true,
  }) async {
    setState(() {
      _loading = showLoading || _loans.isEmpty;
      _error = null;
    });
    try {
      final loans = await _repository.fetchLoans();
      if (!mounted) return;
      setState(() {
        _loans = loans;
        _loading = false;
        _loadedLoans = true;
      });
      if (markFreshness) {
        unawaited(_markLoansFreshnessSeen());
      }
    } catch (error) {
      if (!mounted) return;
      if (!showLoading && _loans.isNotEmpty) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _autoRefreshLoans() async {
    final freshness = await _freshnessRepository.fetchFreshness(
      since: _loansFreshnessCursor,
      sections: const ['loans'],
    );
    final loans = freshness.sections['loans'];
    if (loans != null && !loans.changed && _loadedLoans) {
      _loansFreshnessCursor = freshness.serverTime;
      return;
    }
    await _loadLoans(showLoading: false, markFreshness: false);
    _loansFreshnessCursor = freshness.serverTime;
  }

  Future<void> _markLoansFreshnessSeen() async {
    try {
      final freshness = await _freshnessRepository.fetchFreshness(
        sections: const ['loans'],
      );
      _loansFreshnessCursor = freshness.serverTime;
    } catch (_) {}
  }

  Future<void> _openLoanDialog({Loan? loan}) async {
    final draft = await showDialog<_LoanDraft>(
      context: context,
      builder: (context) => _LoanDraftDialog(loan: loan),
    );
    if (draft == null) return;
    await _runLoanAction(
      busyLoanId: loan?.id,
      failureMessage: loan == null
          ? 'Could not add this loan. Refreshed latest data.'
          : 'Could not update this loan. Refreshed latest data.',
      action: () async {
        if (loan == null) {
          await _repository.createLoan(
            name: draft.name,
            lender: draft.lender,
            loanType: draft.loanType,
            principalAmount: draft.principalAmount,
            originalPrincipalAmount: draft.originalPrincipalAmount,
            emiAmount: draft.emiAmount,
            currency: draft.currency,
            interestRate: draft.interestRate,
            rateType: draft.rateType,
            totalEmis: draft.totalEmis,
            dueDay: draft.dueDay,
            startDate: draft.startDate,
            category: draft.category,
            notes: draft.notes,
          );
        } else {
          await _repository.updateLoan(
            id: loan.id,
            name: draft.name,
            lender: draft.lender,
            loanType: draft.loanType,
            principalAmount: draft.principalAmount,
            originalPrincipalAmount: draft.originalPrincipalAmount,
            emiAmount: draft.emiAmount,
            currency: draft.currency,
            interestRate: draft.interestRate,
            rateType: draft.rateType,
            totalEmis: draft.totalEmis,
            dueDay: draft.dueDay,
            startDate: draft.startDate,
            category: draft.category,
            notes: draft.notes,
          );
        }
      },
    );
  }

  Future<void> _logPayment(Loan loan) async {
    final draft = await showDialog<_LoanPaymentDraft>(
      context: context,
      builder: (context) => _LoanPaymentDialog(loan: loan),
    );
    if (draft == null) return;
    await _runLoanAction(
      busyLoanId: loan.id,
      successMessage: draft.paymentType == 'emi'
          ? 'EMI logged as expense.'
          : 'Prepayment logged as expense.',
      failureMessage: 'Could not log this payment. Refreshed latest data.',
      action: () async {
        await _repository.logPayment(
          loanId: loan.id,
          paymentType: draft.paymentType,
          amount: draft.amount,
          date: draft.date,
          notes: draft.notes,
        );
      },
    );
  }

  Future<void> _archiveLoan(Loan loan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive loan?'),
        content: Text(loan.name),
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
    await _runLoanAction(
      busyLoanId: loan.id,
      failureMessage: 'Could not archive this loan. Refreshed latest data.',
      action: () async {
        await _repository.archiveLoan(loan.id);
      },
    );
  }

  Future<void> _runLoanAction({
    required Future<void> Function() action,
    required String failureMessage,
    String? successMessage,
    String? busyLoanId,
  }) async {
    setState(() {
      _saving = true;
      _busyLoanId = busyLoanId;
    });
    try {
      await action();
      await _loadLoans();
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
        await _loadLoans(showLoading: false);
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _busyLoanId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeLoans = _loans.where((loan) => !loan.archived).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loans'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadLoans,
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
              onRefresh: () => _loadLoans(showLoading: false),
              onAutoRefresh: _autoRefreshLoans,
              autoRefresh: widget.autoRefresh,
              children: [
                AppEmptyState(title: 'Loans unavailable', subtitle: _error),
              ],
            )
          else
            AppPageContainer(
              onRefresh: () => _loadLoans(showLoading: false),
              onAutoRefresh: _autoRefreshLoans,
              autoRefresh: widget.autoRefresh,
              children: [
                _LoansSummaryCard(
                  loans: activeLoans,
                  onAdd: () => _openLoanDialog(),
                ),
                const SizedBox(height: 16),
                AppSectionHeader(
                  title: 'Active loans',
                  actionLabel: 'Add',
                  onAction: () => _openLoanDialog(),
                ),
                if (activeLoans.isEmpty)
                  AppEmptyState(
                    title: 'No loans logged',
                    actionLabel: 'Add loan',
                    onAction: () => _openLoanDialog(),
                  )
                else
                  ...activeLoans.map(
                    (loan) => _LoanCard(
                      loan: loan,
                      busy: _busyLoanId == loan.id,
                      onLogPayment: () => _logPayment(loan),
                      onEdit: () => _openLoanDialog(loan: loan),
                      onArchive: () => _archiveLoan(loan),
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
        onPressed: _saving ? null : () => _openLoanDialog(),
        icon: const Icon(Icons.account_balance_outlined),
        label: const Text('Add loan'),
      ),
    );
  }
}

class _LoansSummaryCard extends StatelessWidget {
  const _LoansSummaryCard({required this.loans, required this.onAdd});

  final List<Loan> loans;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final monthlyEmis = _sumByCurrency(loans, (loan) => loan.emiAmount);
    final outstanding = _sumByCurrency(
      loans,
      (loan) => loan.estimatedOutstanding,
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
                  'Loan log',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Add loan',
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
              _LoanMetricPill(
                label: 'Active',
                value: loans.length.toString(),
                icon: Icons.account_balance_outlined,
              ),
              _LoanMetricPill(
                label: 'Monthly EMI',
                value: AppMoney.formatCurrencyAmounts(monthlyEmis),
                icon: Icons.event_repeat,
              ),
              _LoanMetricPill(
                label: 'Outstanding',
                value: AppMoney.formatCurrencyAmounts(outstanding),
                icon: Icons.trending_down,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoanMetricPill extends StatelessWidget {
  const _LoanMetricPill({
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
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.primary),
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

class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.loan,
    required this.busy,
    required this.onLogPayment,
    required this.onEdit,
    required this.onArchive,
  });

  final Loan loan;
  final bool busy;
  final VoidCallback onLogPayment;
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
                backgroundColor: colors.secondaryContainer,
                child: Icon(
                  Icons.account_balance_outlined,
                  color: colors.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loan.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _loanSubtitle(loan),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_LoanAction>(
                tooltip: 'Loan actions',
                icon: const Icon(Icons.more_vert),
                onSelected: (action) {
                  switch (action) {
                    case _LoanAction.edit:
                      onEdit();
                    case _LoanAction.archive:
                      onArchive();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _LoanAction.edit,
                    child: _LoanActionRow(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                    ),
                  ),
                  PopupMenuItem(
                    value: _LoanAction.archive,
                    child: _LoanActionRow(
                      icon: Icons.archive_outlined,
                      label: 'Archive',
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LoanInfoChip(
                label: 'EMI',
                value: AppMoney.formatCurrency(loan.emiAmount, loan.currency),
              ),
              _LoanInfoChip(
                label: 'Outstanding',
                value: AppMoney.formatCurrency(
                  loan.estimatedOutstanding,
                  loan.currency,
                ),
              ),
              _LoanInfoChip(label: 'Progress', value: _emiProgress(loan)),
              if (loan.nextDueDate != null)
                _LoanInfoChip(
                  label: 'Next',
                  value: DateFormatter.formatDate(loan.nextDueDate!),
                )
              else
                const _LoanInfoChip(label: 'Next', value: 'Complete'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: busy ? null : onLogPayment,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Log EMI'),
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

class _LoanInfoChip extends StatelessWidget {
  const _LoanInfoChip({required this.label, required this.value});

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

enum _LoanAction { edit, archive }

class _LoanActionRow extends StatelessWidget {
  const _LoanActionRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}

class _LoanDraftDialog extends StatefulWidget {
  const _LoanDraftDialog({this.loan});

  final Loan? loan;

  @override
  State<_LoanDraftDialog> createState() => _LoanDraftDialogState();
}

class _LoanDraftDialogState extends State<_LoanDraftDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _lenderController;
  late final TextEditingController _principalController;
  late final TextEditingController _originalPrincipalController;
  late final TextEditingController _emiController;
  late final TextEditingController _interestController;
  late final TextEditingController _termYearsController;
  late final TextEditingController _termMonthsController;
  late final TextEditingController _categoryController;
  late final TextEditingController _notesController;
  late DateTime _startDate;
  var _currency = 'INR';
  var _loanType = 'Personal';
  var _rateType = 'fixed';
  String? _error;

  @override
  void initState() {
    super.initState();
    final loan = widget.loan;
    _currency = loan?.currency ?? 'INR';
    _loanType = loan?.loanType ?? 'Personal';
    _rateType = loan?.rateType ?? 'fixed';
    if (!_loanTypeOptions.contains(_loanType)) {
      _loanType = 'Other';
    }
    if (!_loanRateTypeOptions.contains(_rateType)) {
      _rateType = 'fixed';
    }
    _startDate = loan?.nextDueDate ?? loan?.startDate ?? DateTime.now();
    _nameController = TextEditingController(text: loan?.name ?? '');
    _lenderController = TextEditingController(text: loan?.lender ?? '');
    _principalController = TextEditingController(
      text: loan == null ? '' : loan.principalAmount.toStringAsFixed(0),
    );
    _originalPrincipalController = TextEditingController(
      text: loan == null || loan.originalPrincipalAmount == 0
          ? ''
          : loan.originalPrincipalAmount.toStringAsFixed(0),
    );
    _emiController = TextEditingController(
      text: loan == null ? '' : loan.emiAmount.toStringAsFixed(0),
    );
    _interestController = TextEditingController(
      text: loan == null || loan.interestRate == 0
          ? ''
          : loan.interestRate.toString(),
    );
    final remainingMonths = loan?.remainingEmis ?? loan?.totalEmis ?? 0;
    _termYearsController = TextEditingController(
      text: remainingMonths <= 0 ? '' : '${remainingMonths ~/ 12}',
    );
    _termMonthsController = TextEditingController(
      text: remainingMonths <= 0 ? '' : '${remainingMonths % 12}',
    );
    _categoryController = TextEditingController(
      text: loan?.category ?? 'Loans / EMI',
    );
    _notesController = TextEditingController(text: loan?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lenderController.dispose();
    _principalController.dispose();
    _originalPrincipalController.dispose();
    _emiController.dispose();
    _interestController.dispose();
    _termYearsController.dispose();
    _termMonthsController.dispose();
    _categoryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    final lender = _lenderController.text.trim();
    final principal = double.tryParse(_principalController.text.trim()) ?? 0;
    final originalPrincipal =
        double.tryParse(_originalPrincipalController.text.trim()) ?? 0;
    final emi = double.tryParse(_emiController.text.trim()) ?? 0;
    final interest = double.tryParse(_interestController.text.trim()) ?? 0;
    final termYears = int.tryParse(_termYearsController.text.trim()) ?? 0;
    final termMonths = int.tryParse(_termMonthsController.text.trim()) ?? 0;
    final totalEmis = (termYears * 12) + termMonths;
    final dueDay = _startDate.day;
    final category = _categoryController.text.trim();
    if (name.isEmpty ||
        principal <= 0 ||
        emi <= 0 ||
        termYears < 0 ||
        termMonths < 0 ||
        termMonths > 11 ||
        totalEmis < 0 ||
        dueDay < 1 ||
        dueDay > 31) {
      setState(() {
        _error =
            'Add a name, positive amounts, and remaining months from 0 to 11.';
      });
      return;
    }
    Navigator.of(context).pop(
      _LoanDraft(
        name: name,
        lender: lender,
        loanType: _loanType,
        principalAmount: principal,
        originalPrincipalAmount: originalPrincipal,
        emiAmount: emi,
        currency: _currency,
        interestRate: interest,
        rateType: _rateType,
        totalEmis: totalEmis,
        dueDay: dueDay,
        startDate: _startDate,
        category: category.isEmpty ? 'Loans / EMI' : category,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.loan != null;
    return AlertDialog(
      title: Text(editing ? 'Edit loan' : 'Add existing loan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Loan name',
                hintText: 'Car loan',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lenderController,
              decoration: const InputDecoration(labelText: 'Lender'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _loanType,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: _loanTypeOptions
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _loanType = value);
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _principalController,
                    decoration: InputDecoration(
                      labelText: 'Remaining principal',
                      prefixText: '$_currency ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _emiController,
                    decoration: InputDecoration(
                      labelText: 'Monthly EMI',
                      prefixText: '$_currency ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _originalPrincipalController,
              decoration: InputDecoration(
                labelText: 'Original amount',
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
              items: _loanCurrencyOptions
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _termYearsController,
                    decoration: const InputDecoration(labelText: 'Years left'),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _termMonthsController,
                    decoration: const InputDecoration(labelText: 'Months left'),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _interestController,
                    decoration: const InputDecoration(
                      labelText: 'Current rate',
                      suffixText: '%',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _rateType,
                    decoration: const InputDecoration(
                      labelText: 'Rate type',
                      border: OutlineInputBorder(),
                    ),
                    items: _loanRateTypeOptions
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(_titleCase(item)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _rateType = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickStartDate,
              icon: const Icon(Icons.event_available_outlined),
              label: Text('Next due ${DateFormatter.formatDate(_startDate)}'),
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Past EMIs stay summarized. New payments are tracked from the next due date.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: 'Category'),
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

class _LoanPaymentDialog extends StatefulWidget {
  const _LoanPaymentDialog({required this.loan});

  final Loan loan;

  @override
  State<_LoanPaymentDialog> createState() => _LoanPaymentDialogState();
}

class _LoanPaymentDialogState extends State<_LoanPaymentDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;
  late DateTime _date;
  var _paymentType = 'emi';
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = widget.loan.nextDueDate ?? DateTime.now();
    _amountController = TextEditingController(
      text: widget.loan.emiAmount.toStringAsFixed(0),
    );
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
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
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Add a positive amount.');
      return;
    }
    Navigator.of(context).pop(
      _LoanPaymentDraft(
        paymentType: _paymentType,
        amount: amount,
        date: _date,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log loan payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'emi',
                  label: Text('EMI'),
                  icon: Icon(Icons.event_repeat),
                ),
                ButtonSegment(
                  value: 'prepayment',
                  label: Text('Prepay'),
                  icon: Icon(Icons.savings_outlined),
                ),
              ],
              selected: {_paymentType},
              onSelectionChanged: (value) {
                setState(() => _paymentType = value.first);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${widget.loan.currency} ',
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

class _LoanDraft {
  const _LoanDraft({
    required this.name,
    required this.lender,
    required this.loanType,
    required this.principalAmount,
    required this.originalPrincipalAmount,
    required this.emiAmount,
    required this.currency,
    required this.interestRate,
    required this.rateType,
    required this.totalEmis,
    required this.dueDay,
    required this.startDate,
    required this.category,
    required this.notes,
  });

  final String name;
  final String lender;
  final String loanType;
  final double principalAmount;
  final double originalPrincipalAmount;
  final double emiAmount;
  final String currency;
  final double interestRate;
  final String rateType;
  final int totalEmis;
  final int dueDay;
  final DateTime startDate;
  final String category;
  final String notes;
}

class _LoanPaymentDraft {
  const _LoanPaymentDraft({
    required this.paymentType,
    required this.amount,
    required this.date,
    required this.notes,
  });

  final String paymentType;
  final double amount;
  final DateTime date;
  final String notes;
}

Map<String, num> _sumByCurrency(
  Iterable<Loan> loans,
  double Function(Loan loan) valueForLoan,
) {
  final amounts = <String, num>{};
  for (final loan in loans) {
    final amount = valueForLoan(loan);
    if (amount.abs() <= 0.005) continue;
    amounts[loan.currency] = (amounts[loan.currency] ?? 0) + amount;
  }
  return amounts;
}

String _loanSubtitle(Loan loan) {
  final parts = <String>[loan.loanType];
  if (loan.lender.trim().isNotEmpty) {
    parts.add(loan.lender.trim());
  }
  if (loan.rateType == 'floating') {
    parts.add('Floating ${loan.interestRate.toStringAsFixed(2)}%');
  } else if (loan.interestRate > 0) {
    parts.add('${loan.interestRate.toStringAsFixed(2)}%');
  }
  parts.add(AppMoney.formatCurrency(loan.principalAmount, loan.currency));
  return parts.join(' - ');
}

String _emiProgress(Loan loan) {
  if (loan.totalEmis <= 0) {
    return '${loan.paidEmiCount} logged';
  }
  return '${loan.paidEmiCount}/${loan.totalEmis}';
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
