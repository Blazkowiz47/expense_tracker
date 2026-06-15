import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/features/activity/view/activity_page.dart';
import 'package:expense_tracker/features/activity/models/activity_feed.dart';
import 'package:expense_tracker/features/activity/repositories/activity_feed_repository.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_member.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:expense_tracker/features/recurring/models/recurring_template.dart';
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
    this.membersByGroup = const {},
  }) : super(client: MockClient((_) async => http.Response('{}', 200)));

  final List<GroupSummary> groups;
  final Map<String, List<GroupExpense>> expensesByGroup;
  final Map<String, List<GroupMember>> membersByGroup;

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

  @override
  Future<List<GroupMember>> getCachedMembers(String groupId) async =>
      membersByGroup[groupId] ?? const [];

  @override
  Future<List<GroupMember>> fetchMembers(String groupId) async =>
      membersByGroup[groupId] ?? const [];
}

class _FakeActivityFeedRepository extends ActivityFeedRepository {
  _FakeActivityFeedRepository(ActivityFeed feed) : this.pages([feed]);

  _FakeActivityFeedRepository.pages(this._pages)
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  final List<ActivityFeed> _pages;
  final List<DateTime?> beforeRequests = [];
  int _requestCount = 0;

  @override
  Future<ActivityFeed> fetchActivity({
    DateTime? since,
    DateTime? before,
    int limit = 80,
    Iterable<String> include = const [
      'personal',
      'group',
      'friend_settlements',
      'group_settlements',
      'recurring',
    ],
  }) async {
    beforeRequests.add(before);
    final index = _requestCount < _pages.length
        ? _requestCount
        : _pages.length - 1;
    _requestCount += 1;
    return _pages[index];
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Stream<AuthUser?> authStateChanges() => Stream<AuthUser?>.value(null);

  @override
  Future<void> login({required String email, required String password}) async {}

  @override
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {}

  @override
  Future<void> signOut() async {}
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

    await _scrollUntilTextVisible(tester, 'Coffee');
    expect(find.text('Coffee'), findsOneWidget);

    await tester.tap(find.text('Coffee'));
    await tester.pumpAndSettle();

    expect(find.text('Edit expense'), findsOneWidget);
  });

  testWidgets('keeps personal activity totals separated by currency', (
    tester,
  ) async {
    final today = DateTime.now();
    final expenses = [
      Expense(
        core: ExpenseCore(
          id: 'expense-usd',
          title: 'Airport snacks',
          amount: 20,
          currency: 'USD',
          category: 'Travel',
          createdAt: today,
        ),
        description: 'Airport snacks',
        paymentMethod: 'card',
      ),
      Expense(
        core: ExpenseCore(
          id: 'expense-nok',
          title: 'Train ticket',
          amount: 30,
          currency: 'NOK',
          category: 'Travel',
          createdAt: today,
        ),
        description: 'Train ticket',
        paymentMethod: 'card',
      ),
    ];
    final expenseRepository = _FakeExpenseRepository(expenses);
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

    expect(find.text('NOK 30.00 / USD 20.00'), findsWidgets);
    expect(find.text('USD 20.00'), findsOneWidget);
    expect(find.text('NOK 30.00'), findsOneWidget);
    expect(find.text('₹50.00'), findsNothing);
  });

  testWidgets('shows family and split group expenses in history', (
    tester,
  ) async {
    final today = DateTime.now();
    final todayLabel =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
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
            date: today,
          ),
        ],
        'group-1': [
          _groupExpense(
            id: 'group-expense-1',
            groupId: 'group-1',
            description: 'Dinner',
            amount: 1500,
            date: today,
          ),
        ],
      },
    );
    addTearDown(expensesBloc.close);
    addTearDown(dashboardCubit.close);
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: UserProfileRepository(),
    );
    addTearDown(authCubit.close);

    await tester.pumpWidget(
      RepositoryProvider<ExpenseRepository>.value(
        value: expenseRepository,
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: expensesBloc),
            BlocProvider.value(value: dashboardCubit),
            BlocProvider.value(value: authCubit),
          ],
          child: MaterialApp(
            theme: ThemeData(splashFactory: InkRipple.splashFactory),
            home: ActivityPage(groupsRepository: groupsRepository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Dinner'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Group · Ski trip · $todayLabel'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Groceries'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Family · Home · $todayLabel'), findsOneWidget);
  });

  testWidgets('filters activity history by search category and currency', (
    tester,
  ) async {
    final today = DateTime.now();
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
      ],
      expensesByGroup: {
        'family-1': [
          _groupExpense(
            id: 'family-groceries',
            groupId: 'family-1',
            description: 'Weekly groceries',
            amount: 80,
            currency: 'USD',
            category: 'Groceries',
            date: today,
          ),
          _groupExpense(
            id: 'family-utilities',
            groupId: 'family-1',
            description: 'Internet bill',
            amount: 1200,
            currency: 'INR',
            category: 'Utilities',
            date: today,
          ),
        ],
      },
    );
    addTearDown(expensesBloc.close);
    addTearDown(dashboardCubit.close);
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: UserProfileRepository(),
    );
    addTearDown(authCubit.close);

    await tester.pumpWidget(
      RepositoryProvider<ExpenseRepository>.value(
        value: expenseRepository,
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: expensesBloc),
            BlocProvider.value(value: dashboardCubit),
            BlocProvider.value(value: authCubit),
          ],
          child: MaterialApp(
            theme: ThemeData(splashFactory: InkRipple.splashFactory),
            home: ActivityPage(groupsRepository: groupsRepository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Search history',
      ),
      'weekly',
    );
    await tester.pumpAndSettle();

    expect(find.text('Weekly groceries'), findsOneWidget);
    expect(find.text('Internet bill'), findsNothing);
    expect(find.text('1 match in this period'), findsOneWidget);

    await tester.tap(find.text('All categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groceries').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('All currencies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD').last);
    await tester.pumpAndSettle();

    expect(find.text('Weekly groceries'), findsOneWidget);
    expect(find.text('Internet bill'), findsNothing);
  });

  testWidgets('filters activity history to missing group receipts', (
    tester,
  ) async {
    final today = DateTime.now();
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
      ],
      expensesByGroup: {
        'family-1': [
          _groupExpense(
            id: 'missing-receipt',
            groupId: 'family-1',
            description: 'Pharmacy',
            amount: 300,
            category: 'Health',
            date: today,
          ),
          _groupExpense(
            id: 'has-receipt',
            groupId: 'family-1',
            description: 'School books',
            amount: 700,
            category: 'School and kids',
            attachments: const ['https://example.com/bill.jpg'],
            date: today,
          ),
        ],
      },
    );
    addTearDown(expensesBloc.close);
    addTearDown(dashboardCubit.close);
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: UserProfileRepository(),
    );
    addTearDown(authCubit.close);

    await tester.pumpWidget(
      RepositoryProvider<ExpenseRepository>.value(
        value: expenseRepository,
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: expensesBloc),
            BlocProvider.value(value: dashboardCubit),
            BlocProvider.value(value: authCubit),
          ],
          child: MaterialApp(
            theme: ThemeData(splashFactory: InkRipple.splashFactory),
            home: ActivityPage(groupsRepository: groupsRepository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Missing receipt'));
    await tester.pumpAndSettle();

    await _scrollUntilTextVisible(tester, 'Pharmacy');
    expect(find.text('Pharmacy'), findsOneWidget);
    expect(find.text('School books'), findsNothing);
    expect(find.text('1 match in this period'), findsOneWidget);
  });

  testWidgets(
    'shows settlement and recurring events without adding to spend total',
    (tester) async {
      final today = DateTime.now();
      final expenseRepository = _FakeExpenseRepository();
      final expensesBloc = ExpensesBloc(repository: expenseRepository);
      final dashboardCubit = DashboardSnapshotCubit(
        repository: const MockDashboardSnapshotRepository(),
      )..load();
      final activityFeedRepository = _FakeActivityFeedRepository(
        ActivityFeed(
          serverTime: today.toUtc(),
          tombstones: const ActivityFeedTombstones(),
          entries: [
            ActivityFeedEntry(
              kind: ActivityFeedEntryKind.friendSettlement,
              id: 'friend-settlement-1',
              date: today,
              updatedAt: today,
              viewerUid: 'alice',
              payer: const ActivityUser(uid: 'alice', displayName: 'Alice'),
              receiver: const ActivityUser(uid: 'bob', displayName: 'Bob'),
              settlement: ActivitySettlement(
                id: 'friend-settlement-1',
                payerUid: 'alice',
                receiverUid: 'bob',
                amount: 25,
                currency: 'USD',
                createdAt: today,
              ),
            ),
            ActivityFeedEntry(
              kind: ActivityFeedEntryKind.groupSettlement,
              id: 'group-settlement-1',
              date: today,
              updatedAt: today,
              viewerUid: 'alice',
              group: const GroupSummary(
                id: 'family-1',
                name: 'Home',
                groupType: GroupType.family,
                memberCount: 2,
              ),
              payer: const ActivityUser(uid: 'bob', displayName: 'Bob'),
              receiver: const ActivityUser(uid: 'alice', displayName: 'Alice'),
              settlement: ActivitySettlement(
                id: 'group-settlement-1',
                groupId: 'family-1',
                payerUid: 'bob',
                receiverUid: 'alice',
                amount: 50,
                currency: 'INR',
                createdAt: today,
              ),
            ),
            ActivityFeedEntry(
              kind: ActivityFeedEntryKind.recurringConfirmation,
              id: 'occurrence-1',
              date: today,
              updatedAt: today,
              viewerUid: 'alice',
              recurringOccurrence: RecurringOccurrence(
                id: 'occurrence-1',
                templateId: 'template-1',
                period: '2026-06',
                kind: 'income',
                title: 'Salary',
                category: 'Salary',
                currency: 'INR',
                expectedAmount: 30000,
                actualAmount: 30500,
                dueDate: today,
                actualDate: today,
                status: 'confirmed',
              ),
            ),
          ],
        ),
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
              home: ActivityPage(
                groupsRepository: _FakeGroupsRepository(),
                activityFeedRepository: activityFeedRepository,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You paid Bob'), findsOneWidget);
      expect(find.text('Bob paid you'), findsOneWidget);
      expect(find.text('Received Salary'), findsOneWidget);
      expect(find.text('₹0.00'), findsOneWidget);
      expect(find.text('USD 25.00'), findsOneWidget);
      expect(find.text('₹50.00'), findsOneWidget);
      expect(find.text('₹30,500.00'), findsOneWidget);
    },
  );

  testWidgets('loads older activity event pages', (tester) async {
    final today = DateTime.now();
    final older = today.subtract(const Duration(days: 1));
    final expenseRepository = _FakeExpenseRepository();
    final expensesBloc = ExpensesBloc(repository: expenseRepository);
    final dashboardCubit = DashboardSnapshotCubit(
      repository: const MockDashboardSnapshotRepository(),
    )..load();
    final activityFeedRepository = _FakeActivityFeedRepository.pages([
      ActivityFeed(
        serverTime: today.toUtc(),
        tombstones: const ActivityFeedTombstones(),
        hasMore: true,
        nextCursor: today.toUtc(),
        entries: [
          ActivityFeedEntry(
            kind: ActivityFeedEntryKind.friendSettlement,
            id: 'friend-settlement-new',
            date: today,
            updatedAt: today,
            viewerUid: 'alice',
            payer: const ActivityUser(uid: 'alice', displayName: 'Alice'),
            receiver: const ActivityUser(uid: 'bob', displayName: 'Bob'),
            settlement: ActivitySettlement(
              id: 'friend-settlement-new',
              payerUid: 'alice',
              receiverUid: 'bob',
              amount: 25,
              currency: 'USD',
              createdAt: today,
            ),
          ),
        ],
      ),
      ActivityFeed(
        serverTime: today.toUtc(),
        tombstones: const ActivityFeedTombstones(),
        entries: [
          ActivityFeedEntry(
            kind: ActivityFeedEntryKind.friendSettlement,
            id: 'friend-settlement-old',
            date: older,
            updatedAt: older,
            viewerUid: 'alice',
            payer: const ActivityUser(uid: 'bob', displayName: 'Bob'),
            receiver: const ActivityUser(uid: 'alice', displayName: 'Alice'),
            settlement: ActivitySettlement(
              id: 'friend-settlement-old',
              payerUid: 'bob',
              receiverUid: 'alice',
              amount: 10,
              currency: 'USD',
              createdAt: older,
            ),
          ),
        ],
      ),
    ]);
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
            home: ActivityPage(
              groupsRepository: _FakeGroupsRepository(),
              activityFeedRepository: activityFeedRepository,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You paid Bob'), findsOneWidget);
    expect(find.text('Load older'), findsOneWidget);

    await tester.tap(find.text('Load older'));
    await tester.pumpAndSettle();

    expect(activityFeedRepository.beforeRequests, [null, today.toUtc()]);
    expect(find.text('Bob paid you'), findsOneWidget);
    expect(find.text('USD 10.00'), findsOneWidget);
    expect(find.text('Load older'), findsNothing);
  });

  testWidgets('opens split group expense edit mode from activity', (
    tester,
  ) async {
    final today = DateTime.now();
    final expenseRepository = _FakeExpenseRepository();
    final expensesBloc = ExpensesBloc(repository: expenseRepository);
    final dashboardCubit = DashboardSnapshotCubit(
      repository: const MockDashboardSnapshotRepository(),
    )..load();
    final groupsRepository = _FakeGroupsRepository(
      groups: const [
        GroupSummary(
          id: 'group-1',
          name: 'Ski trip',
          groupType: GroupType.split,
          memberCount: 2,
        ),
      ],
      membersByGroup: const {
        'group-1': [
          GroupMember(uid: 'user-1', displayName: 'You', email: '', phone: ''),
          GroupMember(uid: 'user-2', displayName: 'Alex', email: '', phone: ''),
        ],
      },
      expensesByGroup: {
        'group-1': [
          _groupExpense(
            id: 'group-expense-1',
            groupId: 'group-1',
            description: 'Dinner',
            amount: 1500,
            date: today,
          ),
        ],
      },
    );
    addTearDown(expensesBloc.close);
    addTearDown(dashboardCubit.close);
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: UserProfileRepository(),
    );
    addTearDown(authCubit.close);

    await tester.pumpWidget(
      RepositoryProvider<ExpenseRepository>.value(
        value: expenseRepository,
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: expensesBloc),
            BlocProvider.value(value: dashboardCubit),
            BlocProvider.value(value: authCubit),
          ],
          child: MaterialApp(
            theme: ThemeData(splashFactory: InkRipple.splashFactory),
            home: ActivityPage(groupsRepository: groupsRepository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    await _scrollUntilTextVisible(tester, 'Dinner');
    await tester.tap(find.text('Dinner'));
    await tester.pumpAndSettle();

    expect(find.text('Edit group expense'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Dinner'), findsOneWidget);
  });
}

Future<void> _scrollUntilTextVisible(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

GroupExpense _groupExpense({
  required String id,
  required String groupId,
  required String description,
  required double amount,
  required DateTime date,
  String currency = 'INR',
  String category = '',
  List<String> attachments = const [],
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
    currency: currency,
    category: category,
    description: description,
    attachments: attachments,
    date: date,
    createdAt: date,
    updatedAt: date,
  );
}
