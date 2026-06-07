import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
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
  Expense? updatedExpense;

  @override
  Future<void> updateExpense(Expense expense) async {
    updatedExpense = expense;
    this.expense = expense;
  }

  @override
  List<Expense> getExpenses() => [expense];
}

void main() {
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
          child: AddExpensePage(expense: existing),
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
          child: AddExpensePage(expense: existing),
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
    'ios edit mode changes currency category and payment',
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
            child: AddExpensePage(expense: existing),
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
      await tester.tap(find.text('Travel'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(CupertinoButton, 'Card').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank transfer'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save expense'));
      await tester.pumpAndSettle();

      expect(repository.updatedExpense, isNotNull);
      expect(repository.updatedExpense!.currency, 'USD');
      expect(repository.updatedExpense!.category, 'Travel');
      expect(repository.updatedExpense!.paymentMethod, 'bank_transfer');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );
}
