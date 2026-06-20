import 'dart:async';

import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/utils/date_formatter.dart';
import 'package:expense_tracker/core/utils/platform_widget.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/accounts/models/financial_account.dart';
import 'package:expense_tracker/features/accounts/repositories/api_accounts_repository.dart';
import 'package:expense_tracker/features/credit_cards/models/credit_card.dart';
import 'package:expense_tracker/features/credit_cards/repositories/api_credit_cards_repository.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/expenses/repositories/bill_ai_repository.dart';
import 'package:expense_tracker/features/expenses/repositories/payment_sources_cache.dart';
import 'package:expense_tracker/features/profile/models/user_profile.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:expense_tracker/features/receipts/widgets/receipt_line_items_review.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
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
    this.accountsRepository,
    this.creditCardsRepository,
    super.key,
  });

  final Expense? expense;
  final bool initialBillUpload;
  final String? initialCategory;
  final String? initialDescription;
  final double? initialAmount;
  final String? initialCurrency;
  final String? initialPaymentMethod;
  final ApiAccountsRepository? accountsRepository;
  final ApiCreditCardsRepository? creditCardsRepository;

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  static const double _formMaxWidth = 1180;
  static const _paymentSourceTimeout = Duration(seconds: 45);
  static const _accountPaymentPrefix = 'account:';
  static const _creditCardPaymentPrefix = 'credit_card:';
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
  final _tagsController = TextEditingController();
  final _reimbursementPayerController = TextEditingController(text: 'Company');
  final _reimbursementAmountController = TextEditingController();
  final _billRepository = BillAiRepository();
  final _profileRepository = UserProfileRepository();
  final _picker = ImagePicker();
  late final ApiAccountsRepository _accountsRepository;
  late final ApiCreditCardsRepository _creditCardsRepository;
  http.Client? _client;

  bool _saving = false;
  bool _extractingBill = false;
  String? _error;
  String? _paymentSourcesError;
  String? _billMessage;
  BillExtractionResult? _billResult;
  List<BillLineItem> _receiptItems = const [];
  String _billJobId = '';
  List<FinancialAccount> _accounts = const [];
  List<CreditCardAccount> _creditCards = const [];
  DateTime _expenseDate = DateTime.now();
  String _category = 'Personal';
  String _currency = 'INR';
  String _paymentMethod = 'cash';
  String _destinationAccount = '';
  bool _loadedDefaultPayment = false;
  bool _loadedPaymentSources = false;
  bool _loadingPaymentSources = false;
  String? _pendingDefaultPaymentMethod;
  bool _savePaymentAsDefault = false;
  bool _reimbursable = false;

  bool get _editing => widget.expense != null;
  bool get _isSelfTransfer =>
      _category.trim().toLowerCase().startsWith('savings') ||
      widget.expense?.sourceDestinationAccountId?.trim().isNotEmpty == true ||
      widget.expense?.sourceDestinationAccountName?.trim().isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    if (widget.accountsRepository == null ||
        widget.creditCardsRepository == null) {
      _client = http.Client();
    }
    _accountsRepository =
        widget.accountsRepository ??
        ApiAccountsRepository(client: _client ?? http.Client());
    _creditCardsRepository =
        widget.creditCardsRepository ??
        ApiCreditCardsRepository(client: _client ?? http.Client());
    _applyCachedPaymentSources();
    final expense = widget.expense;
    if (expense != null) {
      final descriptionParts = _splitDescription(
        expense.description,
        expense.title,
      );
      _descriptionController.text = descriptionParts.title;
      _notesController.text = descriptionParts.notes;
      _tagsController.text = _formatTags(expense.tags);
      _amountController.text = expense.amount.toStringAsFixed(2);
      final reimbursement = expense.reimbursement;
      if (reimbursement?.isActive == true) {
        _reimbursable = true;
        _reimbursementPayerController.text = reimbursement!.payer;
        _reimbursementAmountController.text = reimbursement.expectedAmount
            .toStringAsFixed(2);
      }
      _expenseDate = expense.createdAt;
      _category = _normalizedCategory(expense.category ?? 'Personal');
      _currency = _normalizedChoice(expense.currency, _currencies, 'INR');
      _paymentMethod = _normalizedPaymentMethod(
        expense.paymentMethod ?? 'cash',
      );
      final destinationId = expense.sourceDestinationAccountId?.trim();
      final destinationName = expense.sourceDestinationAccountName?.trim();
      if (destinationId != null && destinationId.isNotEmpty) {
        _destinationAccount = _accountPaymentValue(destinationId);
      } else if (destinationName != null && destinationName.isNotEmpty) {
        _destinationAccount = destinationName;
      }
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
        _category = _normalizedCategory(initialCategory);
      }
      if (initialAmount != null && initialAmount > 0) {
        _amountController.text = initialAmount.toStringAsFixed(2);
      }
      if (initialCurrency != null && initialCurrency.isNotEmpty) {
        _currency = _normalizedChoice(initialCurrency, _currencies, 'INR');
      }
      if (initialPaymentMethod != null && initialPaymentMethod.isNotEmpty) {
        _paymentMethod = _normalizedPaymentMethod(initialPaymentMethod);
      }
    }
    if (widget.initialBillUpload && expense == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _uploadBill();
        }
      });
    }
    _loadPaymentSources();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadDefaultPaymentMethod();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    _reimbursementPayerController.dispose();
    _reimbursementAmountController.dispose();
    _client?.close();
    super.dispose();
  }

  Future<void> _loadDefaultPaymentMethod() async {
    if (_loadedDefaultPayment ||
        _editing ||
        widget.initialPaymentMethod?.trim().isNotEmpty == true) {
      return;
    }
    _loadedDefaultPayment = true;
    final user = context.read<AuthCubit?>()?.state.user;
    if (user == null) return;
    UserProfile? profile;
    try {
      profile = await _profileRepository.fetchProfile(fallback: user);
    } catch (_) {
      profile = UserProfile(
        uid: user.uid,
        displayName: user.displayName,
        email: user.email,
        photoUrl: user.photoUrl,
        onboardingCompleted: user.onboardingCompleted,
        defaultPaymentMethod: user.defaultPaymentMethod,
      );
    }
    if (!mounted) return;
    final method = profile.defaultPaymentMethod.trim();
    if (method.isEmpty) return;
    setState(() {
      _pendingDefaultPaymentMethod = method;
      _applyPendingDefaultPaymentMethod();
    });
  }

  void _applyCachedPaymentSources() {
    final cached = PaymentSourcesCache.snapshot;
    if (cached == null) return;
    _accounts = cached.accounts;
    _creditCards = cached.creditCards;
    _loadedPaymentSources = true;
  }

  Future<void> _loadPaymentSources({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _loadingPaymentSources = true;
        _paymentSourcesError = null;
      });
    }
    final result = await PaymentSourcesCache.load(
      accountsRepository: _accountsRepository,
      creditCardsRepository: _creditCardsRepository,
      timeout: _paymentSourceTimeout,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() {
      _accounts = result.snapshot.accounts;
      _creditCards = result.snapshot.creditCards;
      _loadedPaymentSources = true;
      _loadingPaymentSources = false;
      _applyPendingDefaultPaymentMethod();
      final availablePaymentChoices = _isSelfTransfer
          ? _transferPaymentChoices
          : _paymentChoices;
      if (!availablePaymentChoices.contains(_paymentMethod)) {
        _paymentMethod = 'cash';
      }
      _currency = _currencyForPayment(_paymentMethod) ?? _currency;
      if (_isSelfTransfer &&
          _destinationAccount.isEmpty &&
          _accounts.any((account) => !account.archived)) {
        _destinationAccount = _accountPaymentValue(
          _accounts.firstWhere((account) => !account.archived).id,
        );
      }
      _paymentSourcesError = _paymentSourcesMessage(
        accounts: _accounts,
        creditCards: _creditCards,
        accountsError: result.accountsError,
        creditCardsError: result.creditCardsError,
      );
    });
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
    final selectedCard = _selectedCreditCard;
    final selectedAccount = _selectedAccount;
    final selectedDestinationAccount = _selectedDestinationAccount;
    final tags = _billResult == null
        ? _parseTags(_tagsController.text)
        : const <String>[];
    final effectiveCurrency = selectedCard?.currency ?? _currency;
    final effectivePaymentMethod = selectedCard == null
        ? _paymentMethod
        : 'card';
    final preservedSourceAccount = effectivePaymentMethod == 'paid_previously';
    final reimbursement = _reimbursable
        ? ReimbursementInfo(
            status: 'expected',
            payer: _reimbursementPayerController.text.trim().isEmpty
                ? 'Company'
                : _reimbursementPayerController.text.trim(),
            expectedAmount:
                _parseAmount(_reimbursementAmountController.text) ?? amount,
            receivedAmount: existing?.reimbursement?.receivedAmount ?? 0,
            currency: effectiveCurrency,
            linkedIncomeIds:
                existing?.reimbursement?.linkedIncomeIds ?? const [],
          )
        : null;
    final expense = Expense(
      core: ExpenseCore(
        id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: description,
        amount: amount,
        currency: effectiveCurrency,
        category: _category,
        createdAt: _expenseDate,
      ),
      description: _composeDescription(description, notes),
      paymentMethod: effectivePaymentMethod,
      sourceType: existing?.sourceType,
      sourceAccountId:
          selectedAccount?.id ??
          (preservedSourceAccount ? existing?.sourceAccountId : null),
      sourceAccountName: selectedAccount == null
          ? (preservedSourceAccount ? existing?.sourceAccountName : null)
          : _accountLabel(selectedAccount),
      sourceDestinationAccountId:
          selectedDestinationAccount?.id ??
          existing?.sourceDestinationAccountId,
      sourceDestinationAccountName: selectedDestinationAccount == null
          ? existing?.sourceDestinationAccountName
          : _accountLabel(selectedDestinationAccount),
      sourcePaymentType: existing?.sourcePaymentType,
      sourcePeriod: existing?.sourcePeriod,
      sourceSetupKey: existing?.sourceSetupKey,
      sourceExpenseId: existing?.sourceExpenseId,
      tags: tags,
      reimbursement: reimbursement,
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
      if (!_editing && selectedCard != null) {
        await _creditCardsRepository.logSpend(
          cardId: selectedCard.id,
          amount: amount,
          category: _category,
          description: _composeDescription(description, notes),
          date: _expenseDate,
          tags: tags,
          reimbursement: reimbursement?.toJson(),
        );
        bloc.add(const RefreshExpenses());
      } else if (_editing) {
        bloc.add(
          UpdateExpense(
            expense: expense,
            receiptItems: receiptItems,
            billJobId: _billJobId,
          ),
        );
      } else {
        bloc.add(
          CreateExpense(
            expense: expense,
            receiptItems: receiptItems,
            billJobId: _billJobId,
          ),
        );
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

      await _saveDefaultPaymentIfRequested(effectivePaymentMethod);
      if (!mounted) return;

      if (addAnother && !_editing) {
        setState(() {
          _saving = false;
          _descriptionController.clear();
          _amountController.clear();
          _notesController.clear();
          _tagsController.clear();
          _billResult = null;
          _receiptItems = const [];
          _billJobId = '';
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

  Future<void> _saveDefaultPaymentIfRequested(String paymentMethod) async {
    if (!_savePaymentAsDefault || paymentMethod.trim().isEmpty) return;
    final user = context.read<AuthCubit?>()?.state.user;
    if (user == null) return;
    await _profileRepository.updateDefaultPaymentMethod(
      user: user,
      paymentMethod: paymentMethod,
    );
  }

  Future<void> _uploadBill() async {
    setState(() {
      _extractingBill = true;
      _error = null;
      _billMessage = 'Extracting bill on the backend...';
      _billJobId = '';
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
      final jobId = await _billRepository.uploadBill(
        bytes: await picked.readAsBytes(),
        fileName: picked.name,
        contentType: _contentTypeFor(picked.name),
      );
      if (!mounted) return;
      setState(() {
        _extractingBill = false;
        _billJobId = jobId;
        _billMessage =
            'Receipt uploaded. You can choose payment now; autofill will appear when processing finishes.';
      });
      unawaited(_pollBillExtraction(jobId));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _extractingBill = false;
        _error = 'Bill upload failed: $error';
        _billMessage = null;
      });
    }
  }

  Future<void> _pollBillExtraction(String jobId) async {
    try {
      final result = await _billRepository.waitForJob(jobId);
      if (!mounted) return;
      _applyBillExtractionResult(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _extractingBill = false;
        _error = 'Bill extraction failed: $error';
      });
    }
  }

  void _applyBillExtractionResult(BillExtractionResult result) {
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
      _billJobId = result.jobId;
      _tagsController.clear();
      if (result.dateExtracted) {
        _expenseDate = result.date;
      }
      _category = _normalizedChoice(result.category, _categories, 'Personal');
      _currency = _normalizedChoice(result.currency, _currencies, 'INR');
      _extractingBill = false;
      _billMessage =
          'Receipt processed (${(result.confidence * 100).toStringAsFixed(0)}% confidence).';
    });
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

  List<String> _parseTags(String value) => _normalizeTags(
    value
        .split(RegExp(r'[,;#\n]'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty),
  );

  List<String> _normalizeTags(Iterable<String> values) {
    final tags = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final tag = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (tag.isEmpty || seen.contains(tag)) continue;
      tags.add(tag);
      seen.add(tag);
    }
    return tags;
  }

  String _formatTags(List<String> tags) => tags.join(', ');

  String? _paymentSourcesMessage({
    required List<FinancialAccount> accounts,
    required List<CreditCardAccount> creditCards,
    required Object? accountsError,
    required Object? creditCardsError,
  }) {
    if (accountsError == null && creditCardsError == null) {
      final hasAccounts = accounts.any((account) => !account.archived);
      final hasCards = creditCards.any((card) => !card.archived);
      if (!hasAccounts && !hasCards) {
        return 'No bank accounts or credit cards found for this signed-in account yet. Add them from Account, or sync local data if you moved to the hosted app.';
      }
      return null;
    }
    final details = [
      accountsError,
      creditCardsError,
    ].whereType<Object>().map((error) => error.toString()).join(' ');
    if (details.contains('(401)') || details.contains('MISSING_TOKEN')) {
      return 'Sign in again to load bank accounts and credit cards.';
    }
    if (details.contains('TimeoutException')) {
      return 'Bank accounts and credit cards are taking longer than usual to load. The backend may still be waking up.';
    }
    if (accountsError != null && creditCardsError != null) {
      return 'Bank accounts and credit cards could not be loaded. You can still save with Cash.';
    }
    if (accountsError != null) {
      return 'Bank accounts could not be loaded. Credit cards are still available.';
    }
    return 'Credit cards could not be loaded. Bank accounts are still available.';
  }

  String _normalizedChoice(
    String value,
    List<String> choices,
    String fallback,
  ) {
    final lower = value.trim().toLowerCase();
    if (lower.startsWith(_accountPaymentPrefix) ||
        lower.startsWith(_creditCardPaymentPrefix)) {
      return lower;
    }
    return choices.firstWhere(
      (choice) => choice.toLowerCase() == lower,
      orElse: () => fallback,
    );
  }

  String _normalizedCategory(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Personal';
    return _categories.firstWhere(
      (choice) => choice.toLowerCase() == trimmed.toLowerCase(),
      orElse: () => trimmed,
    );
  }

  String _normalizedPaymentMethod(String value, {String fallback = 'cash'}) {
    final trimmed = value.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith(_accountPaymentPrefix) ||
        lower.startsWith(_creditCardPaymentPrefix)) {
      final parts = lower.split(':');
      if (parts.length == 2 && parts.last.trim().isNotEmpty) {
        return '${parts.first}:${parts.last.trim()}';
      }
    }
    return _normalizedChoice(trimmed, _paymentMethods, fallback);
  }

  bool _paymentMethodCanBeApplied(String value) {
    if (_paymentChoices.contains(value)) return true;
    return false;
  }

  void _applyPendingDefaultPaymentMethod() {
    final pending = _pendingDefaultPaymentMethod?.trim();
    if (pending == null || pending.isEmpty) return;
    final normalized = _normalizedPaymentMethod(pending);
    if (!_paymentMethodCanBeApplied(normalized)) {
      if (_loadedPaymentSources) {
        _pendingDefaultPaymentMethod = null;
      }
      return;
    }
    _pendingDefaultPaymentMethod = null;
    _paymentMethod = normalized;
    _currency = _currencyForPayment(_paymentMethod) ?? _currency;
  }

  List<String> get _categoryChoices {
    final choices = <String>[..._categories];
    if (!choices.any(
      (choice) => choice.toLowerCase() == _category.toLowerCase(),
    )) {
      choices.add(_category);
    }
    return choices;
  }

  List<String> get _paymentChoices {
    final choices = <String>[
      'cash',
      ..._accounts
          .where((account) => !account.archived)
          .map((account) => _accountPaymentValue(account.id)),
      ..._creditCards
          .where((card) => !card.archived)
          .map((card) => _creditCardPaymentValue(card.id)),
    ];
    if (_paymentMethod == 'paid_previously' ||
        (_editing && _isLegacyPaymentMethod(_paymentMethod))) {
      choices.add(_paymentMethod);
    }
    if ((_paymentMethod.startsWith(_accountPaymentPrefix) ||
            _paymentMethod.startsWith(_creditCardPaymentPrefix)) &&
        !choices.contains(_paymentMethod)) {
      choices.add(_paymentMethod);
    }
    return choices;
  }

  List<String> get _transferPaymentChoices {
    final choices = <String>[
      'cash',
      'paid_previously',
      ..._accounts
          .where((account) => !account.archived)
          .map((account) => _accountPaymentValue(account.id)),
    ];
    if (!choices.contains(_paymentMethod)) {
      choices.add(_paymentMethod);
    }
    return choices;
  }

  List<String> get _destinationChoices {
    final choices = _accounts
        .where((account) => !account.archived)
        .map((account) => _accountPaymentValue(account.id))
        .toList(growable: true);
    if (_destinationAccount.isNotEmpty &&
        !choices.contains(_destinationAccount)) {
      choices.add(_destinationAccount);
    }
    return choices;
  }

  CreditCardAccount? get _selectedCreditCard {
    if (!_paymentMethod.startsWith(_creditCardPaymentPrefix)) return null;
    final id = _paymentMethod.substring(_creditCardPaymentPrefix.length);
    for (final card in _creditCards) {
      if (card.id == id && !card.archived) return card;
    }
    return null;
  }

  bool _isLegacyPaymentMethod(String value) {
    return const {'card', 'upi', 'bank_transfer', 'other'}.contains(value);
  }

  FinancialAccount? get _selectedAccount {
    if (!_paymentMethod.startsWith(_accountPaymentPrefix)) return null;
    final id = _paymentMethod.substring(_accountPaymentPrefix.length);
    for (final account in _accounts) {
      if (account.id == id && !account.archived) return account;
    }
    return null;
  }

  FinancialAccount? get _selectedDestinationAccount {
    if (!_destinationAccount.startsWith(_accountPaymentPrefix)) return null;
    final id = _destinationAccount.substring(_accountPaymentPrefix.length);
    for (final account in _accounts) {
      if (account.id == id && !account.archived) return account;
    }
    return null;
  }

  String? _currencyForPayment(String value) {
    if (value.startsWith(_accountPaymentPrefix)) {
      final id = value.substring(_accountPaymentPrefix.length);
      for (final account in _accounts) {
        if (account.id == id) return account.currency;
      }
    }
    if (value.startsWith(_creditCardPaymentPrefix)) {
      final id = value.substring(_creditCardPaymentPrefix.length);
      for (final card in _creditCards) {
        if (card.id == id) return card.currency;
      }
    }
    return null;
  }

  void _setPaymentMethod(String value) {
    setState(() {
      _paymentMethod = value;
      _currency = _currencyForPayment(value) ?? _currency;
    });
  }

  void _setDestinationAccount(String value) {
    setState(() {
      _destinationAccount = value;
    });
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
        maxWidth: _formMaxWidth,
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
                        values: _categoryChoices,
                        onChanged: (value) => setState(() => _category = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DropdownField(
                        label: _isSelfTransfer ? 'Paid from' : 'Payment',
                        value: _paymentMethod,
                        values: _isSelfTransfer
                            ? _transferPaymentChoices
                            : _paymentChoices,
                        labelFor: _paymentLabel,
                        onChanged: _setPaymentMethod,
                      ),
                    ),
                  ],
                ),
                if (_isSelfTransfer && _destinationChoices.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _DropdownField(
                    label: 'Paid to',
                    value: _destinationAccount.isEmpty
                        ? _destinationChoices.first
                        : _destinationAccount,
                    values: _destinationChoices,
                    labelFor: _destinationLabel,
                    onChanged: _setDestinationAccount,
                  ),
                ],
                if (_paymentMethod == 'paid_previously') ...[
                  const SizedBox(height: 8),
                  const _PaidPreviouslyNotice(),
                ],
                if (_paymentMethod.startsWith(_creditCardPaymentPrefix)) ...[
                  const SizedBox(height: 8),
                  _PaymentSourceNotice(
                    message:
                        'This will update the selected credit card balance.',
                  ),
                ],
                if (_loadingPaymentSources) ...[
                  const SizedBox(height: 8),
                  const _PaymentSourceLoadingNotice(),
                ],
                if (_paymentSourcesError != null) ...[
                  const SizedBox(height: 8),
                  _PaymentSourceNotice(
                    message: _paymentSourcesError!,
                    onRetry: () => _loadPaymentSources(forceRefresh: true),
                  ),
                ],
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _savePaymentAsDefault,
                  title: const Text('Use this as my default payment method'),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: _saving
                      ? null
                      : (value) {
                          setState(
                            () => _savePaymentAsDefault = value ?? false,
                          );
                        },
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _reimbursable,
                  title: const Text('Reimbursable'),
                  subtitle: const Text(
                    'Track money you expect back from work or someone else.',
                  ),
                  onChanged: _saving
                      ? null
                      : (value) {
                          setState(() {
                            _reimbursable = value;
                            if (value &&
                                _reimbursementAmountController.text
                                    .trim()
                                    .isEmpty) {
                              _reimbursementAmountController.text =
                                  _amountController.text.trim();
                            }
                          });
                        },
                ),
                if (_reimbursable) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _reimbursementPayerController,
                          decoration: const InputDecoration(
                            labelText: 'Expected from',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _reimbursementAmountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Expected amount',
                            prefixText: '$_currency ',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_billResult == null) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Tags',
                      hintText: 'guilty pleasure, chocolate, vegetables',
                      border: OutlineInputBorder(),
                    ),
                  ),
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
          constraints: const BoxConstraints(maxWidth: _formMaxWidth),
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
              constraints: const BoxConstraints(maxWidth: _formMaxWidth),
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
                            values: _categoryChoices,
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
                            values: _paymentChoices,
                            selectedValue: _paymentMethod,
                            labelFor: _paymentLabel,
                            onSelected: (value) {
                              if (!mounted) return;
                              _setPaymentMethod(value);
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
                      if (_paymentMethod.startsWith(_creditCardPaymentPrefix))
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: _PaymentSourceNotice(
                            message:
                                'This will update the selected credit card balance.',
                          ),
                        ),
                      if (_loadingPaymentSources)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: _PaymentSourceLoadingNotice(),
                        ),
                      if (_paymentSourcesError != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: _PaymentSourceNotice(
                            message: _paymentSourcesError!,
                            onRetry: () =>
                                _loadPaymentSources(forceRefresh: true),
                          ),
                        ),
                      CupertinoFormRow(
                        prefix: const Text('Default payment'),
                        child: CupertinoSwitch(
                          value: _savePaymentAsDefault,
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _savePaymentAsDefault = value,
                                ),
                        ),
                      ),
                      CupertinoFormRow(
                        prefix: const Text('Reimbursable'),
                        child: CupertinoSwitch(
                          value: _reimbursable,
                          onChanged: _saving
                              ? null
                              : (value) {
                                  setState(() {
                                    _reimbursable = value;
                                    if (value &&
                                        _reimbursementAmountController.text
                                            .trim()
                                            .isEmpty) {
                                      _reimbursementAmountController.text =
                                          _amountController.text.trim();
                                    }
                                  });
                                },
                        ),
                      ),
                      if (_reimbursable) ...[
                        CupertinoFormRow(
                          prefix: const Text('Expected from'),
                          child: CupertinoTextField(
                            controller: _reimbursementPayerController,
                            textAlign: TextAlign.end,
                          ),
                        ),
                        CupertinoFormRow(
                          prefix: const Text('Expected amount'),
                          child: CupertinoTextField(
                            controller: _reimbursementAmountController,
                            placeholder: _amountController.text,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                      if (_billResult == null)
                        CupertinoFormRow(
                          prefix: const Text('Tags'),
                          child: CupertinoTextField(
                            controller: _tagsController,
                            placeholder: 'guilty pleasure, chocolate',
                            textAlign: TextAlign.end,
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

  String _paymentLabel(String value) {
    if (value.startsWith(_accountPaymentPrefix)) {
      final id = value.substring(_accountPaymentPrefix.length);
      for (final account in _accounts) {
        if (account.id == id) {
          return _accountLabel(account);
        }
      }
      return 'Bank account';
    }
    if (value.startsWith(_creditCardPaymentPrefix)) {
      final id = value.substring(_creditCardPaymentPrefix.length);
      for (final card in _creditCards) {
        if (card.id == id) {
          return _creditCardLabel(card);
        }
      }
      return 'Credit card';
    }
    return switch (value) {
      'cash' => 'Cash',
      'card' => 'Card',
      'upi' => 'UPI',
      'bank_transfer' => 'Bank transfer',
      'paid_previously' => 'Paid previously',
      _ => 'Other',
    };
  }

  String _destinationLabel(String value) {
    if (value.startsWith(_accountPaymentPrefix)) {
      final id = value.substring(_accountPaymentPrefix.length);
      for (final account in _accounts) {
        if (account.id == id) {
          return _accountLabel(account);
        }
      }
    }
    return value.trim().isEmpty ? 'Bank account' : value;
  }

  String _accountPaymentValue(String id) => '$_accountPaymentPrefix$id';

  String _creditCardPaymentValue(String id) => '$_creditCardPaymentPrefix$id';

  String _accountLabel(FinancialAccount account) {
    final institution = account.institution.trim();
    final suffix = institution.isEmpty ? '' : ' - $institution';
    return '${account.name}$suffix';
  }

  String _creditCardLabel(CreditCardAccount card) {
    final last4 = card.last4.trim();
    final issuer = card.issuer.trim();
    final details = [
      if (issuer.isNotEmpty) issuer,
      if (last4.isNotEmpty) '•••• $last4',
    ].join(' · ');
    return details.isEmpty ? card.name : '${card.name} - $details';
  }
}

class _PaymentSourceNotice extends StatelessWidget {
  const _PaymentSourceNotice({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Text(message, style: textStyle)),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

class _PaymentSourceLoadingNotice extends StatelessWidget {
  const _PaymentSourceLoadingNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Loading bank accounts and credit cards...',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
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
    final selectedValue = values.contains(value) && value.trim().isNotEmpty
        ? value
        : (values.isNotEmpty ? values.first : null);
    return DropdownButtonFormField<String>(
      initialValue: selectedValue,
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
