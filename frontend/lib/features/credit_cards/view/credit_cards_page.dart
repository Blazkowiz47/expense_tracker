import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/utils/date_formatter.dart';
import 'package:expense_tracker/features/credit_cards/models/credit_card.dart';
import 'package:expense_tracker/features/credit_cards/repositories/api_credit_cards_repository.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _cardCurrencies = <String>['NOK', 'INR', 'USD', 'EUR', 'GBP'];
const _spendCategories = <String>[
  'Groceries',
  'Food',
  'Transport',
  'Shopping',
  'Bills',
  'Travel',
  'Health',
  'Personal',
];
const _networks = <String>['Visa', 'Mastercard', 'Amex', 'Other'];

class CreditCardsPage extends StatefulWidget {
  const CreditCardsPage({this.repository, super.key});

  final ApiCreditCardsRepository? repository;

  @override
  State<CreditCardsPage> createState() => _CreditCardsPageState();
}

class _CreditCardsPageState extends State<CreditCardsPage> {
  late final ApiCreditCardsRepository _repository;
  http.Client? _client;
  var _cards = <CreditCardAccount>[];
  var _loading = true;
  var _saving = false;
  String? _busyCardId;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.repository == null) {
      _client = http.Client();
      _repository = ApiCreditCardsRepository(client: _client!);
    } else {
      _repository = widget.repository!;
    }
    _loadCards();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  Future<void> _loadCards({bool showLoading = true}) async {
    setState(() {
      _loading = showLoading || _cards.isEmpty;
      _error = null;
    });
    try {
      final cards = await _repository.fetchCards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
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

  Future<void> _openCardDialog({CreditCardAccount? card}) async {
    final draft = await showDialog<_CardDraft>(
      context: context,
      builder: (context) => _CardDraftDialog(card: card),
    );
    if (draft == null) return;
    await _runCardAction(
      busyCardId: card?.id,
      failureMessage: card == null
          ? 'Could not add this credit card.'
          : 'Could not update this credit card.',
      action: () async {
        if (card == null) {
          await _repository.createCard(
            name: draft.name,
            issuer: draft.issuer,
            network: draft.network,
            last4: draft.last4,
            currency: draft.currency,
            creditLimit: draft.creditLimit,
            currentBalance: draft.currentBalance,
            statementDay: draft.statementDay,
            dueDay: draft.dueDay,
            familyVisibility: draft.familyVisibility,
            notes: draft.notes,
          );
        } else {
          await _repository.updateCard(
            id: card.id,
            name: draft.name,
            issuer: draft.issuer,
            network: draft.network,
            last4: draft.last4,
            currency: draft.currency,
            creditLimit: draft.creditLimit,
            currentBalance: draft.currentBalance,
            statementDay: draft.statementDay,
            dueDay: draft.dueDay,
            familyVisibility: draft.familyVisibility,
            notes: draft.notes,
          );
        }
      },
    );
  }

  Future<void> _logSpend(CreditCardAccount card) async {
    final draft = await showDialog<_SpendDraft>(
      context: context,
      builder: (context) => _SpendDraftDialog(card: card),
    );
    if (draft == null) return;
    await _runCardAction(
      busyCardId: card.id,
      successMessage: 'Card spend logged as an expense.',
      failureMessage: 'Could not log this card spend.',
      action: () async {
        await _repository.logSpend(
          cardId: card.id,
          amount: draft.amount,
          category: draft.category,
          description: draft.description,
          date: draft.date,
        );
      },
    );
  }

  Future<void> _recordPayment(CreditCardAccount card) async {
    final draft = await showDialog<_PaymentDraft>(
      context: context,
      builder: (context) => _PaymentDraftDialog(card: card),
    );
    if (draft == null) return;
    await _runCardAction(
      busyCardId: card.id,
      successMessage: 'Credit card payment recorded.',
      failureMessage: 'Could not record this credit card payment.',
      action: () async {
        await _repository.updateCard(
          id: card.id,
          name: card.name,
          issuer: card.issuer,
          network: card.network,
          last4: card.last4,
          currency: card.currency,
          creditLimit: card.creditLimit,
          currentBalance: card.currentBalance - draft.amount,
          statementDay: card.statementDay,
          dueDay: card.dueDay,
          familyVisibility: card.familyVisibility,
          notes: card.notes,
        );
      },
    );
  }

  Future<void> _archiveCard(CreditCardAccount card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive credit card?'),
        content: Text(card.name),
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
    await _runCardAction(
      busyCardId: card.id,
      failureMessage: 'Could not archive this credit card.',
      action: () => _repository.archiveCard(card.id),
    );
  }

  Future<void> _runCardAction({
    required Future<void> Function() action,
    required String failureMessage,
    String? successMessage,
    String? busyCardId,
  }) async {
    setState(() {
      _saving = true;
      _busyCardId = busyCardId;
    });
    try {
      await action();
      await _loadCards(showLoading: false);
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
        await _loadCards(showLoading: false);
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _busyCardId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCards = _cards.where((card) => !card.archived).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit cards'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _loadCards(showLoading: false),
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
              onRefresh: () => _loadCards(showLoading: false),
              children: [
                AppEmptyState(
                  title: 'Credit cards unavailable',
                  subtitle: _error,
                ),
              ],
            )
          else
            AppPageContainer(
              onRefresh: () => _loadCards(showLoading: false),
              children: [
                _CreditCardsSummary(cards: activeCards, onAdd: _openCardDialog),
                const SizedBox(height: 16),
                AppSectionHeader(
                  title: 'Cards',
                  actionLabel: 'Add',
                  onAction: _openCardDialog,
                ),
                if (activeCards.isEmpty)
                  AppEmptyState(
                    title: 'No credit cards logged',
                    subtitle:
                        'Add the current outstanding balance, limit, statement day, and due day.',
                    actionLabel: 'Add card',
                    onAction: _openCardDialog,
                  )
                else
                  ...activeCards.map(
                    (card) => _CreditCardTile(
                      card: card,
                      busy: _busyCardId == card.id,
                      onLogSpend: () => _logSpend(card),
                      onRecordPayment: () => _recordPayment(card),
                      onEdit: () => _openCardDialog(card: card),
                      onArchive: () => _archiveCard(card),
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
        onPressed: _saving ? null : _openCardDialog,
        icon: const Icon(Icons.credit_card),
        label: const Text('Add card'),
      ),
    );
  }
}

class _CreditCardsSummary extends StatelessWidget {
  const _CreditCardsSummary({required this.cards, required this.onAdd});

  final List<CreditCardAccount> cards;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final outstanding = _sumByCurrency(cards, (card) => card.currentBalance);
    final cycleSpend = _sumByCurrency(cards, (card) => card.currentCycleSpend);
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Credit card log',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Add credit card',
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
                label: 'Cards',
                value: cards.length.toString(),
                icon: Icons.credit_card,
              ),
              _MetricPill(
                label: 'Outstanding',
                value: AppMoney.formatCurrencyAmounts(outstanding),
                icon: Icons.trending_down,
                debt: true,
              ),
              _MetricPill(
                label: 'This cycle',
                value: AppMoney.formatCurrencyAmounts(cycleSpend),
                icon: Icons.receipt_long_outlined,
                debt: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreditCardTile extends StatelessWidget {
  const _CreditCardTile({
    required this.card,
    required this.busy,
    required this.onLogSpend,
    required this.onRecordPayment,
    required this.onEdit,
    required this.onArchive,
  });

  final CreditCardAccount card;
  final bool busy;
  final VoidCallback onLogSpend;
  final VoidCallback onRecordPayment;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statement = card.statementDate == null
        ? 'Statement day ${card.statementDay}'
        : 'Statement ${DateFormatter.formatDate(card.statementDate!)}';
    final due = card.paymentDueDate == null
        ? 'Due day ${card.dueDay}'
        : 'Due ${DateFormatter.formatDate(card.paymentDueDate!)}';
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: colors.errorContainer,
                child: Icon(Icons.credit_card, color: colors.onErrorContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (card.issuer.isNotEmpty) card.issuer,
                        if (card.network.isNotEmpty) card.network,
                        if (card.last4.isNotEmpty) '•••• ${card.last4}',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                label: 'Outstanding',
                value: AppMoney.formatCurrency(
                  card.currentBalance,
                  card.currency,
                ),
              ),
              _InfoChip(
                label: 'Available',
                value: AppMoney.formatCurrency(
                  card.availableCredit,
                  card.currency,
                ),
              ),
              _InfoChip(
                label: 'Cycle spend',
                value: AppMoney.formatCurrency(
                  card.currentCycleSpend,
                  card.currency,
                ),
              ),
              _InfoChip(label: 'Statement', value: statement),
              _InfoChip(label: 'Payment', value: due),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : onLogSpend,
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('Log spend'),
              ),
              OutlinedButton.icon(
                onPressed: busy || card.currentBalance <= 0
                    ? null
                    : onRecordPayment,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Record payment'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: busy ? null : onArchive,
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archive'),
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
    required this.icon,
    this.debt = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool debt;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 174,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (debt ? colors.errorContainer : colors.primaryContainer)
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: debt ? colors.error : colors.primary),
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

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

class _CardDraftDialog extends StatefulWidget {
  const _CardDraftDialog({this.card});

  final CreditCardAccount? card;

  @override
  State<_CardDraftDialog> createState() => _CardDraftDialogState();
}

class _CardDraftDialogState extends State<_CardDraftDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _issuerController;
  late final TextEditingController _last4Controller;
  late final TextEditingController _limitController;
  late final TextEditingController _balanceController;
  late final TextEditingController _notesController;
  var _currency = 'NOK';
  var _network = 'Visa';
  var _statementDay = 1;
  var _dueDay = 15;
  var _familyVisibility = 'private';
  String? _error;

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    _currency = card?.currency ?? 'NOK';
    if (!_cardCurrencies.contains(_currency)) _currency = 'NOK';
    _network = card?.network.isNotEmpty == true ? card!.network : 'Visa';
    if (!_networks.contains(_network)) _network = 'Other';
    _statementDay = card?.statementDay ?? 1;
    _dueDay = card?.dueDay ?? 15;
    _familyVisibility = card?.familyVisibility ?? 'private';
    _nameController = TextEditingController(text: card?.name ?? '');
    _issuerController = TextEditingController(text: card?.issuer ?? '');
    _last4Controller = TextEditingController(text: card?.last4 ?? '');
    _limitController = TextEditingController(
      text: card == null || card.creditLimit == 0
          ? ''
          : card.creditLimit.toStringAsFixed(0),
    );
    _balanceController = TextEditingController(
      text: card == null || card.currentBalance == 0
          ? ''
          : card.currentBalance.toStringAsFixed(2),
    );
    _notesController = TextEditingController(text: card?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _issuerController.dispose();
    _last4Controller.dispose();
    _limitController.dispose();
    _balanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final limit = _parseMoney(_limitController.text);
    final balance = _parseMoney(_balanceController.text);
    if (name.isEmpty || limit < 0 || balance < 0) {
      setState(() => _error = 'Add a card name and non-negative amounts.');
      return;
    }
    Navigator.of(context).pop(
      _CardDraft(
        name: name,
        issuer: _issuerController.text.trim(),
        network: _network,
        last4: _last4Controller.text.trim(),
        currency: _currency,
        creditLimit: limit,
        currentBalance: balance,
        statementDay: _statementDay,
        dueDay: _dueDay,
        familyVisibility: _familyVisibility,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.card != null;
    return AlertDialog(
      title: Text(editing ? 'Edit credit card' : 'Add credit card'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Card name',
                hintText: 'DNB Mastercard',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _issuerController,
              decoration: const InputDecoration(labelText: 'Bank or issuer'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _network,
              decoration: const InputDecoration(
                labelText: 'Network',
                border: OutlineInputBorder(),
              ),
              items: _networks
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(growable: false),
              onChanged: (value) => setState(() => _network = value ?? 'Visa'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _last4Controller,
              decoration: const InputDecoration(labelText: 'Last 4 digits'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(
                labelText: 'Currency',
                border: OutlineInputBorder(),
              ),
              items: _cardCurrencies
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(growable: false),
              onChanged: (value) => setState(() => _currency = value ?? 'NOK'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _limitController,
              decoration: const InputDecoration(labelText: 'Credit limit'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _balanceController,
              decoration: const InputDecoration(
                labelText: 'Current outstanding balance',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _statementDay,
                    decoration: const InputDecoration(
                      labelText: 'Statement day',
                      border: OutlineInputBorder(),
                    ),
                    items: _days(),
                    onChanged: (value) {
                      if (value != null) setState(() => _statementDay = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _dueDay,
                    decoration: const InputDecoration(
                      labelText: 'Due day',
                      border: OutlineInputBorder(),
                    ),
                    items: _days(),
                    onChanged: (value) {
                      if (value != null) setState(() => _dueDay = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _familyVisibility,
              decoration: const InputDecoration(
                labelText: 'Visibility',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'private', child: Text('Private')),
                DropdownMenuItem(
                  value: 'family',
                  child: Text('Family visible'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _familyVisibility = value ?? 'private'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              minLines: 1,
              maxLines: 3,
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
        FilledButton(onPressed: _submit, child: const Text('Save card')),
      ],
    );
  }
}

class _SpendDraftDialog extends StatefulWidget {
  const _SpendDraftDialog({required this.card});

  final CreditCardAccount card;

  @override
  State<_SpendDraftDialog> createState() => _SpendDraftDialogState();
}

class _SpendDraftDialogState extends State<_SpendDraftDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late DateTime _date;
  var _category = 'Personal';
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _amountController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
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
    final amount = _parseMoney(_amountController.text);
    final description = _descriptionController.text.trim();
    if (amount <= 0 || description.isEmpty) {
      setState(() => _error = 'Add a positive amount and description.');
      return;
    }
    Navigator.of(context).pop(
      _SpendDraft(
        amount: amount,
        category: _category,
        description: description,
        date: _date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Log spend on ${widget.card.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${widget.card.currency} ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: _spendCategories
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(growable: false),
              onChanged: (value) =>
                  setState(() => _category = value ?? 'Personal'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Store or item',
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(DateFormatter.formatDate(_date)),
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
        FilledButton(onPressed: _submit, child: const Text('Log spend')),
      ],
    );
  }
}

class _PaymentDraftDialog extends StatefulWidget {
  const _PaymentDraftDialog({required this.card});

  final CreditCardAccount card;

  @override
  State<_PaymentDraftDialog> createState() => _PaymentDraftDialogState();
}

class _PaymentDraftDialogState extends State<_PaymentDraftDialog> {
  late final TextEditingController _amountController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = _parseMoney(_amountController.text);
    if (amount <= 0) {
      setState(() => _error = 'Add a positive payment amount.');
      return;
    }
    if (amount > widget.card.currentBalance) {
      setState(() => _error = 'Payment cannot exceed outstanding balance.');
      return;
    }
    Navigator.of(context).pop(_PaymentDraft(amount: amount));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Record payment for ${widget.card.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Outstanding ${AppMoney.formatCurrency(widget.card.currentBalance, widget.card.currency)}',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            decoration: InputDecoration(
              labelText: 'Payment amount',
              prefixText: '${widget.card.currency} ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Record payment')),
      ],
    );
  }
}

class _CardDraft {
  const _CardDraft({
    required this.name,
    required this.issuer,
    required this.network,
    required this.last4,
    required this.currency,
    required this.creditLimit,
    required this.currentBalance,
    required this.statementDay,
    required this.dueDay,
    required this.familyVisibility,
    required this.notes,
  });

  final String name;
  final String issuer;
  final String network;
  final String last4;
  final String currency;
  final double creditLimit;
  final double currentBalance;
  final int statementDay;
  final int dueDay;
  final String familyVisibility;
  final String notes;
}

class _SpendDraft {
  const _SpendDraft({
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
  });

  final double amount;
  final String category;
  final String description;
  final DateTime date;
}

class _PaymentDraft {
  const _PaymentDraft({required this.amount});

  final double amount;
}

List<DropdownMenuItem<int>> _days() {
  return List.generate(
    31,
    (index) => DropdownMenuItem(value: index + 1, child: Text('${index + 1}')),
  );
}

double _parseMoney(String value) {
  return double.tryParse(
        value.trim().replaceAll(',', '').replaceAll(' ', ''),
      ) ??
      0;
}

Map<String, double> _sumByCurrency(
  Iterable<CreditCardAccount> cards,
  double Function(CreditCardAccount card) selector,
) {
  final totals = <String, double>{};
  for (final card in cards) {
    totals[card.currency] = (totals[card.currency] ?? 0) + selector(card);
  }
  return totals;
}
