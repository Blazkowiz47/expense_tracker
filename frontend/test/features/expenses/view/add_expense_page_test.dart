import 'dart:async';

import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/features/accounts/models/financial_account.dart';
import 'package:expense_tracker/features/accounts/repositories/api_accounts_repository.dart';
import 'package:expense_tracker/features/credit_cards/models/credit_card.dart';
import 'package:expense_tracker/features/credit_cards/repositories/api_credit_cards_repository.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/expenses/view/add_expense_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeExpenseRepository extends ExpenseRepository {
  _FakeExpenseRepository(this.expense)
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  Expense expense;
  Expense? createdExpense;
  Expense? updatedExpense;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> createExpense(
    Expense expense, {
    List<Map<String, dynamic>> receiptItems = const [],
    String billJobId = '',
  }) async {
    createdExpense = expense;
    this.expense = expense;
  }

  @override
  Future<void> updateExpense(
    Expense expense, {
    List<Map<String, dynamic>> receiptItems = const [],
    String billJobId = '',
  }) async {
    updatedExpense = expense;
    this.expense = expense;
  }

  @override
  List<Expense> getExpenses() => [expense];
}

class _FakeAccountsRepository extends ApiAccountsRepository {
  _FakeAccountsRepository([this.accounts = const [], this.error])
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  final List<FinancialAccount> accounts;
  final Object? error;

  @override
  Future<List<FinancialAccount>> fetchAccounts({
    bool includeArchived = false,
  }) async {
    if (error != null) {
      throw error!;
    }
    return accounts;
  }
}

class _FakeCreditCardsRepository extends ApiCreditCardsRepository {
  _FakeCreditCardsRepository([this.cards = const [], this.error])
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  final List<CreditCardAccount> cards;
  final Object? error;
  String? loggedCardId;
  double? loggedAmount;
  String? loggedCategory;
  String? loggedDescription;
  DateTime? loggedDate;

  @override
  Future<List<CreditCardAccount>> fetchCards({
    bool includeArchived = false,
  }) async {
    if (error != null) {
      throw error!;
    }
    return cards;
  }

  @override
  Future<CreditCardSpendResult> logSpend({
    required String cardId,
    required double amount,
    required String category,
    required String description,
    required DateTime date,
    List<String> tags = const [],
    Map<String, dynamic>? reimbursement,
  }) async {
    loggedCardId = cardId;
    loggedAmount = amount;
    loggedCategory = category;
    loggedDescription = description;
    loggedDate = date;
    return CreditCardSpendResult(
      card: cards.firstWhere((card) => card.id == cardId),
      expense: const <String, dynamic>{'id': 'expense-card'},
    );
  }
}

void main() {
  testWidgets('planned expense opens with amount currency and category', (
    tester,
  ) async {
    final repository = _FakeExpenseRepository(
      Expense(
        core: ExpenseCore(
          id: 'seed',
          title: 'Seed',
          amount: 1,
          currency: 'NOK',
          category: 'Personal',
          createdAt: DateTime(2026, 6, 16),
        ),
      ),
    );
    final bloc = ExpensesBloc(repository: repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: BlocProvider.value(
          value: bloc,
          child: AddExpensePage(
            initialCategory: 'Rent and housing',
            initialDescription: 'Rent and housing',
            initialAmount: 8000,
            initialCurrency: 'NOK',
            initialPaymentMethod: 'paid_previously',
            accountsRepository: _FakeAccountsRepository(),
            creditCardsRepository: _FakeCreditCardsRepository(),
          ),
        ),
      ),
    );

    expect(find.widgetWithText(TextField, 'Rent and housing'), findsOneWidget);
    expect(find.widgetWithText(TextField, '8000.00'), findsOneWidget);
    expect(find.text('Rent and housing'), findsWidgets);
    expect(find.text('NOK'), findsWidgets);
    expect(find.text('Paid previously'), findsOneWidget);
    expect(
      find.text(
        'Counts toward this month without treating it as a new cash, card, or bank payment.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(repository.createdExpense, isNotNull);
    expect(repository.createdExpense!.category, 'Rent and housing');
    expect(repository.createdExpense!.amount, 8000);
    expect(repository.createdExpense!.currency, 'NOK');
    expect(repository.createdExpense!.paymentMethod, 'paid_previously');
  });

  testWidgets('planned expense keeps initial bank account payment source', (
    tester,
  ) async {
    final repository = _FakeExpenseRepository(
      Expense(
        core: ExpenseCore(
          id: 'seed',
          title: 'Seed',
          amount: 1,
          currency: 'NOK',
          category: 'Personal',
          createdAt: DateTime(2026, 6, 16),
        ),
      ),
    );
    final bloc = ExpensesBloc(repository: repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: BlocProvider.value(
          value: bloc,
          child: AddExpensePage(
            initialCategory: 'Groceries',
            initialDescription: 'Rema 1000',
            initialAmount: 125,
            initialCurrency: 'NOK',
            initialPaymentMethod: 'account:account-1',
            accountsRepository: _FakeAccountsRepository([
              _account(id: 'account-1', name: 'DNB current'),
            ]),
            creditCardsRepository: _FakeCreditCardsRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DNB current - DNB'), findsOneWidget);

    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(repository.createdExpense, isNotNull);
    expect(repository.createdExpense!.paymentMethod, 'account:account-1');
    expect(repository.createdExpense!.sourceAccountId, 'account-1');
    expect(repository.createdExpense!.sourceAccountName, 'DNB current - DNB');
  });

  testWidgets('manual expense saves normalized tags', (tester) async {
    final repository = _FakeExpenseRepository(
      Expense(
        core: ExpenseCore(
          id: 'seed',
          title: 'Seed',
          amount: 1,
          currency: 'NOK',
          category: 'Personal',
          createdAt: DateTime(2026, 6, 16),
        ),
      ),
    );
    final bloc = ExpensesBloc(repository: repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: BlocProvider.value(
          value: bloc,
          child: AddExpensePage(
            accountsRepository: _FakeAccountsRepository(),
            creditCardsRepository: _FakeCreditCardsRepository(),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'Brownie');
    await tester.enterText(find.byType(TextField).at(1), '52.60');
    await tester.enterText(
      _tagFieldFinder(),
      'Guilty Pleasure, chocolate, chocolate',
    );
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(repository.createdExpense, isNotNull);
    expect(repository.createdExpense!.tags, ['guilty pleasure', 'chocolate']);
  });

  testWidgets('manual expense can be marked reimbursable', (tester) async {
    final repository = _FakeExpenseRepository(
      Expense(
        core: ExpenseCore(
          id: 'seed',
          title: 'Seed',
          amount: 1,
          currency: 'NOK',
          category: 'Personal',
          createdAt: DateTime(2026, 6, 16),
        ),
      ),
    );
    final bloc = ExpensesBloc(repository: repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: BlocProvider.value(
          value: bloc,
          child: AddExpensePage(
            accountsRepository: _FakeAccountsRepository(),
            creditCardsRepository: _FakeCreditCardsRepository(),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'Client taxi');
    await tester.enterText(find.byType(TextField).at(1), '500');
    final reimbursableSwitch = find.widgetWithText(
      SwitchListTile,
      'Reimbursable',
    );
    await tester.ensureVisible(reimbursableSwitch);
    await tester.pumpAndSettle();
    await tester.tap(reimbursableSwitch);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Company'), 'ACME');
    await tester.enterText(find.widgetWithText(TextField, '500').last, '450');

    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    final reimbursement = repository.createdExpense?.reimbursement;
    expect(reimbursement, isNotNull);
    expect(reimbursement!.payer, 'ACME');
    expect(reimbursement.expectedAmount, 450);
    expect(reimbursement.currency, 'INR');
  });

  testWidgets('edit mode updates an existing expense with details', (
    tester,
  ) async {
    final existing = Expense(
      core: ExpenseCore(
        id: 'expense-1',
        title: 'Coffee',
        amount: 120,
        currency: 'INR',
        category: 'Food',
        createdAt: DateTime(2026, 4, 24),
      ),
      description: 'Coffee\nLatte with oat milk',
      paymentMethod: 'card',
    );
    final repository = _FakeExpenseRepository(existing);
    final bloc = ExpensesBloc(repository: repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: BlocProvider.value(
          value: bloc,
          child: AddExpensePage(
            expense: existing,
            accountsRepository: _FakeAccountsRepository(),
            creditCardsRepository: _FakeCreditCardsRepository(),
          ),
        ),
      ),
    );

    expect(find.text('Edit expense'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Coffee'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Latte with oat milk'),
      findsOneWidget,
    );
    expect(find.text('Food'), findsWidgets);
    expect(find.text('Card'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Lunch');
    await tester.enterText(find.byType(TextField).at(1), '250,50');
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(repository.updatedExpense, isNotNull);
    expect(repository.updatedExpense!.id, 'expense-1');
    expect(repository.updatedExpense!.title, 'Lunch');
    expect(
      repository.updatedExpense!.description,
      'Lunch\nLatte with oat milk',
    );
    expect(repository.updatedExpense!.amount, 250.50);
    expect(repository.updatedExpense!.category, 'Food');
    expect(repository.updatedExpense!.paymentMethod, 'card');
    expect(repository.updatedExpense!.createdAt, existing.createdAt);
  });

  testWidgets('rejects non-finite amounts', (tester) async {
    final existing = Expense(
      core: ExpenseCore(
        id: 'expense-1',
        title: 'Coffee',
        amount: 120,
        currency: 'INR',
        category: 'Food',
        createdAt: DateTime(2026, 4, 24),
      ),
      description: 'Coffee',
      paymentMethod: 'card',
    );
    final repository = _FakeExpenseRepository(existing);
    final bloc = ExpensesBloc(repository: repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: BlocProvider.value(
          value: bloc,
          child: AddExpensePage(
            expense: existing,
            accountsRepository: _FakeAccountsRepository(),
            creditCardsRepository: _FakeCreditCardsRepository(),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).at(1), 'NaN');
    await tester.tap(find.text('Save expense'));
    await tester.pump();

    expect(find.text('Enter a valid amount greater than 0.'), findsOneWidget);
    expect(repository.updatedExpense, isNull);
  });

  testWidgets(
    'ios edit mode changes category and payment source',
    (tester) async {
      final existing = Expense(
        core: ExpenseCore(
          id: 'expense-1',
          title: 'Coffee',
          amount: 120,
          currency: 'INR',
          category: 'Food',
          createdAt: DateTime(2026, 4, 24),
        ),
        description: 'Coffee',
        paymentMethod: 'card',
      );
      final repository = _FakeExpenseRepository(existing);
      final bloc = ExpensesBloc(repository: repository);
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: bloc,
            child: AddExpensePage(
              expense: existing,
              accountsRepository: _FakeAccountsRepository([
                _account(id: 'account-1', name: 'DNB current'),
              ]),
              creditCardsRepository: _FakeCreditCardsRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(CupertinoButton, 'INR').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(CupertinoButton, 'Food').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Travel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Travel'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(CupertinoButton, 'Card').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('DNB current - DNB'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DNB current - DNB'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(CupertinoButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repository.updatedExpense, isNotNull);
      expect(repository.updatedExpense!.currency, 'NOK');
      expect(repository.updatedExpense!.category, 'Travel');
      expect(repository.updatedExpense!.paymentMethod, 'account:account-1');
      expect(repository.updatedExpense!.sourceAccountId, 'account-1');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets('payment dropdown includes accounts and logs card spend', (
    tester,
  ) async {
    final repository = _FakeExpenseRepository(
      Expense(
        core: ExpenseCore(
          id: 'seed',
          title: 'Seed',
          amount: 1,
          currency: 'NOK',
          category: 'Personal',
          createdAt: DateTime(2026, 6, 16),
        ),
      ),
    );
    final bloc = ExpensesBloc(repository: repository);
    addTearDown(bloc.close);
    final cardRepository = _FakeCreditCardsRepository([
      _card(id: 'card-1', name: 'SAS Mastercard', issuer: 'DNB', last4: '1234'),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: BlocProvider.value(
          value: bloc,
          child: AddExpensePage(
            accountsRepository: _FakeAccountsRepository([
              _account(id: 'account-1', name: 'DNB current'),
            ]),
            creditCardsRepository: cardRepository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    expect(find.text('DNB current - DNB'), findsOneWidget);
    await tester.tap(find.text('SAS Mastercard - DNB · •••• 1234'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Coffee');
    await tester.enterText(find.byType(TextField).at(1), '59');
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(repository.createdExpense, isNull);
    expect(cardRepository.loggedCardId, 'card-1');
    expect(cardRepository.loggedAmount, 59);
    expect(cardRepository.loggedCategory, 'Personal');
    expect(cardRepository.loggedDescription, 'Coffee');
  });

  testWidgets('payment sources keep cards when accounts fail', (tester) async {
    final repository = _FakeExpenseRepository(
      Expense(
        core: ExpenseCore(
          id: 'seed',
          title: 'Seed',
          amount: 1,
          currency: 'NOK',
          category: 'Personal',
          createdAt: DateTime(2026, 6, 16),
        ),
      ),
    );
    final bloc = ExpensesBloc(repository: repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: BlocProvider.value(
          value: bloc,
          child: AddExpensePage(
            accountsRepository: _FakeAccountsRepository(
              const [],
              Exception('accounts request failed (500): backend unavailable'),
            ),
            creditCardsRepository: _FakeCreditCardsRepository([
              _card(id: 'card-1', name: 'Morrow', issuer: 'Morrow'),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Bank accounts could not be loaded. Credit cards are still available.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    expect(find.text('Morrow - Morrow'), findsOneWidget);
  });

  testWidgets('empty payment sources explain why only cash is available', (
    tester,
  ) async {
    final repository = _FakeExpenseRepository(
      Expense(
        core: ExpenseCore(
          id: 'seed',
          title: 'Seed',
          amount: 1,
          currency: 'NOK',
          category: 'Personal',
          createdAt: DateTime(2026, 6, 16),
        ),
      ),
    );
    final bloc = ExpensesBloc(repository: repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: BlocProvider.value(
          value: bloc,
          child: AddExpensePage(
            accountsRepository: _FakeAccountsRepository(),
            creditCardsRepository: _FakeCreditCardsRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No bank accounts or credit cards found for this signed-in account yet. Add them from Account, or sync local data if you moved to the hosted app.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    expect(find.text('Cash'), findsWidgets);
  });

  testWidgets('payment source timeout explains backend wakeup and can retry', (
    tester,
  ) async {
    final repository = _FakeExpenseRepository(
      Expense(
        core: ExpenseCore(
          id: 'seed',
          title: 'Seed',
          amount: 1,
          currency: 'NOK',
          category: 'Personal',
          createdAt: DateTime(2026, 6, 16),
        ),
      ),
    );
    final bloc = ExpensesBloc(repository: repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: BlocProvider.value(
          value: bloc,
          child: AddExpensePage(
            accountsRepository: _FakeAccountsRepository(
              const [],
              TimeoutException('accounts timed out'),
            ),
            creditCardsRepository: _FakeCreditCardsRepository(
              const [],
              TimeoutException('cards timed out'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Bank accounts and credit cards are taking longer than usual to load. The backend may still be waking up.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'legacy generic payment methods are not offered for new expenses',
    (tester) async {
      final repository = _FakeExpenseRepository(
        Expense(
          core: ExpenseCore(
            id: 'seed',
            title: 'Seed',
            amount: 1,
            currency: 'NOK',
            category: 'Personal',
            createdAt: DateTime(2026, 6, 16),
          ),
        ),
      );
      final bloc = ExpensesBloc(repository: repository);
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: BlocProvider.value(
            value: bloc,
            child: AddExpensePage(
              initialPaymentMethod: 'card',
              accountsRepository: _FakeAccountsRepository([
                _account(id: 'account-1', name: 'DNB current'),
              ]),
              creditCardsRepository: _FakeCreditCardsRepository([
                _card(id: 'card-1', name: 'Morrow', issuer: 'Morrow'),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();

      expect(find.text('DNB current - DNB'), findsOneWidget);
      expect(find.text('Morrow - Morrow'), findsOneWidget);
      expect(find.text('Card'), findsNothing);
      expect(find.text('UPI'), findsNothing);
      expect(find.text('Bank transfer'), findsNothing);
      expect(find.text('Other'), findsNothing);
    },
  );

  testWidgets('edit mode preserves setup account and custom category', (
    tester,
  ) async {
    final existing = Expense(
      core: ExpenseCore(
        id: 'setup-savings',
        title: 'For SGP Trip',
        amount: 2000,
        currency: 'NOK',
        category: 'Savings - For SGP Trip',
        createdAt: DateTime(2026, 6, 17),
      ),
      description: 'For SGP Trip',
      paymentMethod: 'paid_previously',
      sourceType: 'setup_month_entry',
      sourceAccountId: 'account-1',
      sourceAccountName: 'DNB current - DNB',
      sourceDestinationAccountId: 'account-2',
      sourceDestinationAccountName: 'DNB savings - DNB',
      sourcePaymentType: 'expense',
      sourcePeriod: '2026-06',
      sourceSetupKey: 'savings:sgp-trip',
    );
    final repository = _FakeExpenseRepository(existing);
    final bloc = ExpensesBloc(repository: repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: BlocProvider.value(
          value: bloc,
          child: AddExpensePage(
            expense: existing,
            accountsRepository: _FakeAccountsRepository([
              _account(id: 'account-1', name: 'DNB current'),
              _account(id: 'account-2', name: 'DNB savings'),
            ]),
            creditCardsRepository: _FakeCreditCardsRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Savings - For SGP Trip'), findsWidgets);
    expect(find.text('DNB savings - DNB'), findsOneWidget);
    expect(find.text('Paid previously'), findsOneWidget);
    expect(find.text('Paid from'), findsOneWidget);
    expect(find.text('Paid to'), findsOneWidget);

    await tester.tap(find.text('Paid previously'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DNB current - DNB').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(repository.updatedExpense, isNotNull);
    expect(repository.updatedExpense!.category, 'Savings - For SGP Trip');
    expect(repository.updatedExpense!.paymentMethod, 'account:account-1');
    expect(repository.updatedExpense!.sourceAccountId, 'account-1');
    expect(repository.updatedExpense!.sourceAccountName, 'DNB current - DNB');
    expect(repository.updatedExpense!.sourceDestinationAccountId, 'account-2');
    expect(
      repository.updatedExpense!.sourceDestinationAccountName,
      'DNB savings - DNB',
    );
  });
}

Finder _tagFieldFinder() {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == 'Tags',
  );
}

FinancialAccount _account({
  required String id,
  required String name,
  String institution = 'DNB',
}) {
  return FinancialAccount(
    id: id,
    name: name,
    institution: institution,
    accountType: 'checking',
    currency: 'NOK',
    openingBalance: 1000,
    currentBalance: 1000,
    balanceAsOf: DateTime(2026, 6, 17),
    familyVisibility: 'private',
    notes: '',
    archived: false,
    archivedAt: null,
    createdAt: DateTime(2026, 6, 17),
    updatedAt: DateTime(2026, 6, 17),
  );
}

CreditCardAccount _card({
  required String id,
  required String name,
  String issuer = '',
  String last4 = '',
}) {
  return CreditCardAccount(
    id: id,
    name: name,
    issuer: issuer,
    network: 'Mastercard',
    last4: last4,
    currency: 'NOK',
    creditLimit: 50000,
    currentBalance: 1200,
    availableCredit: 48800,
    balanceAsOf: DateTime(2026, 6, 17),
    statementDay: 1,
    dueDay: 15,
    cycleStart: DateTime(2026, 6, 1),
    statementDate: DateTime(2026, 6, 30),
    paymentDueDate: DateTime(2026, 7, 15),
    currentCycleSpend: 1200,
    familyVisibility: 'private',
    notes: '',
    archived: false,
  );
}
