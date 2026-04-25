import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/features/activity/view/activity_page.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeExpenseRepository extends ExpenseRepository {
  _FakeExpenseRepository(this.expense)
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  Expense expense;

  @override
  Future<void> refresh() async {}

  @override
  List<Expense> getExpenses() => [expense];
}

void main() {
  testWidgets('opens edit mode from a personal activity expense', (
    tester,
  ) async {
    final expense = Expense(
      core: ExpenseCore(
        id: 'expense-1',
        title: 'Coffee',
        amount: 120,
        currency: 'INR',
        category: 'Personal',
        createdAt: DateTime.now(),
      ),
      description: 'Coffee',
      paymentMethod: 'cash',
    );
    final expenseRepository = _FakeExpenseRepository(expense);
    final expensesBloc = ExpensesBloc(repository: expenseRepository);
    final dashboardCubit = DashboardSnapshotCubit(
      repository: const MockDashboardSnapshotRepository(),
    )..load();
    addTearDown(expensesBloc.close);
    addTearDown(dashboardCubit.close);

    await tester.pumpWidget(
      RepositoryProvider<ExpenseRepository>.value(
        value: expenseRepository,
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: expensesBloc),
            BlocProvider.value(value: dashboardCubit),
          ],
          child: MaterialApp(
            theme: ThemeData(splashFactory: InkRipple.splashFactory),
            home: const ActivityPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coffee'), findsOneWidget);

    await tester.tap(find.text('Coffee'));
    await tester.pumpAndSettle();

    expect(find.text('Edit expense'), findsOneWidget);
  });
}
