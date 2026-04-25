import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/features/activity/view/activity_page.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeExpenseRepository extends ExpenseRepository {
  _FakeExpenseRepository([this.expenses = const []])
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  List<Expense> expenses;

  @override
  Future<void> refresh() async {}

  @override
  List<Expense> getExpenses() => expenses;
}

class _FakeGroupsRepository extends ApiGroupsRepository {
  _FakeGroupsRepository({
    this.groups = const [],
    this.expensesByGroup = const {},
  }) : super(client: MockClient((_) async => http.Response('{}', 200)));

  final List<GroupSummary> groups;
  final Map<String, List<GroupExpense>> expensesByGroup;

  @override
  Future<List<GroupSummary>> getCachedGroups() async => groups;

  @override
  Future<List<GroupSummary>> fetchGroups() async => groups;

  @override
  Future<List<GroupExpense>> getCachedExpenses(String groupId) async =>
      expensesByGroup[groupId] ?? const [];

  @override
  Future<List<GroupExpense>> fetchExpenses(String groupId) async =>
      expensesByGroup[groupId] ?? const [];
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
    final expenseRepository = _FakeExpenseRepository([expense]);
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
            home: ActivityPage(groupsRepository: _FakeGroupsRepository()),
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

  testWidgets('shows family and split group expenses in history', (
    tester,
  ) async {
    final expenseRepository = _FakeExpenseRepository();
    final expensesBloc = ExpensesBloc(repository: expenseRepository);
    final dashboardCubit = DashboardSnapshotCubit(
      repository: const MockDashboardSnapshotRepository(),
    )..load();
    final groupsRepository = _FakeGroupsRepository(
      groups: const [
        GroupSummary(
          id: 'family-1',
          name: 'Home',
          groupType: GroupType.family,
          memberCount: 3,
        ),
        GroupSummary(
          id: 'group-1',
          name: 'Ski trip',
          groupType: GroupType.split,
          memberCount: 4,
        ),
      ],
      expensesByGroup: {
        'family-1': [
          _groupExpense(
            id: 'family-expense-1',
            groupId: 'family-1',
            description: 'Groceries',
            amount: 900,
            date: DateTime(2026, 4, 24),
          ),
        ],
        'group-1': [
          _groupExpense(
            id: 'group-expense-1',
            groupId: 'group-1',
            description: 'Dinner',
            amount: 1500,
            date: DateTime(2026, 4, 25),
          ),
        ],
      },
    );
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
            home: ActivityPage(groupsRepository: groupsRepository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Group · Ski trip · 2026-04-25'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Groceries'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Family · Home · 2026-04-24'), findsOneWidget);
  });
}

GroupExpense _groupExpense({
  required String id,
  required String groupId,
  required String description,
  required double amount,
  required DateTime date,
}) {
  return GroupExpense(
    id: id,
    groupId: groupId,
    createdBy: 'user-1',
    updatedBy: 'user-1',
    paidBy: 'user-1',
    splitMode: 'equally',
    splitWith: const ['user-1', 'user-2'],
    amount: amount,
    description: description,
    attachments: const [],
    date: date,
    createdAt: date,
    updatedAt: date,
  );
}
