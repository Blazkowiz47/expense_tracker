import 'package:expense_tracker/data/models/freshness_snapshot.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/data/repositories/freshness_repository.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/family/view/family_page.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_member.dart';
import 'package:expense_tracker/features/groups/models/group_settlement.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:expense_tracker/features/groups/view/groups_page.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeGroupsRepository extends ApiGroupsRepository {
  _FakeGroupsRepository(
    this.groups, {
    this.members = const [
      GroupMember(
        uid: 'member-1',
        displayName: 'Nisha',
        email: 'nisha@example.com',
        phone: '',
        role: 'Wife',
      ),
    ],
    this.expenses,
  }) : super(client: MockClient((_) async => http.Response('{}', 200)));

  final List<GroupSummary> groups;
  final List<GroupMember> members;
  final List<GroupExpense>? expenses;
  final List<GroupSettlement> settlements = [];
  int fetchGroupCount = 0;
  ({
    String groupId,
    String memberUid,
    String direction,
    double amount,
    String currency,
  })?
  recordedGroupSettlement;

  @override
  Future<List<GroupSummary>> getCachedGroups() async => const [];

  @override
  Future<List<GroupSummary>> fetchGroups() async {
    fetchGroupCount += 1;
    return groups;
  }

  @override
  Future<List<GroupMember>> getCachedMembers(String groupId) async => const [];

  @override
  Future<List<GroupExpense>> getCachedExpenses(String groupId) async =>
      const [];

  @override
  Future<List<GroupMember>> fetchMembers(String groupId) async => members;

  @override
  Future<List<GroupExpense>> fetchExpenses(String groupId) async =>
      expenses ??
      [
        GroupExpense(
          id: 'expense-1',
          groupId: groupId,
          createdBy: 'member-1',
          updatedBy: 'member-1',
          paidBy: 'member-1',
          splitMode: 'equally',
          splitWith: const ['member-1'],
          amount: 1200,
          category: 'Groceries',
          description: 'Monthly grocery run',
          attachments: const [],
          date: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

  @override
  Future<List<GroupSettlement>> fetchSettlements(String groupId) async =>
      settlements;

  @override
  Future<GroupSettlement> recordSettlement({
    required String groupId,
    required String memberUid,
    required String direction,
    required double amount,
    String currency = 'INR',
    String note = '',
  }) async {
    recordedGroupSettlement = (
      groupId: groupId,
      memberUid: memberUid,
      direction: direction,
      amount: amount,
      currency: currency,
    );
    final settlement = GroupSettlement(
      id: 'settlement-${settlements.length + 1}',
      groupId: groupId,
      payerUid: 'member-1',
      receiverUid: memberUid,
      amount: amount,
      currency: currency,
      createdBy: 'member-1',
      createdAt: DateTime(2026, 6, 7),
    );
    settlements.insert(0, settlement);
    return settlement;
  }
}

class _FakeFreshnessRepository extends FreshnessRepository {
  _FakeFreshnessRepository(this._responses)
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  final List<FreshnessSnapshot> _responses;
  final List<({DateTime? since, List<String> sections})> requests = [];

  @override
  Future<FreshnessSnapshot> fetchFreshness({
    DateTime? since,
    Iterable<String> sections = const [],
  }) async {
    requests.add((since: since, sections: sections.toList(growable: false)));
    final index = requests.length - 1;
    return _responses[index < _responses.length
        ? index
        : _responses.length - 1];
  }
}

class _FakeMonthlyPlanRepository extends MonthlyPlanRepository {
  _FakeMonthlyPlanRepository({
    this.excludedExpenseCount = 0,
    this.excludedActualsByCurrency = const {},
  }) : super(client: MockClient((_) async => http.Response('{}', 200)));

  final int excludedExpenseCount;
  final Map<String, double> excludedActualsByCurrency;

  @override
  Future<MonthlyPlan> fetchPlan({
    required String month,
    String? groupId,
  }) async {
    return MonthlyPlan(
      month: '2026-06',
      groupId: groupId,
      currency: 'INR',
      totalBudget: 5000,
      totalActual: 1200,
      totalRemaining: 3800,
      excludedExpenseCount: excludedExpenseCount,
      excludedActualsByCurrency: excludedActualsByCurrency,
      categories: const [
        MonthlyPlanCategory(
          category: 'Groceries',
          budget: 5000,
          actual: 1200,
          remaining: 3800,
          progress: 0.24,
          overBudget: false,
        ),
      ],
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Stream<AuthUser?> authStateChanges() => Stream<AuthUser?>.value(
    const AuthUser(
      uid: 'member-1',
      email: 'nisha@example.com',
      displayName: 'Nisha',
    ),
  );

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

class _FakeUserProfileRepository extends UserProfileRepository {
  @override
  Future<void> ensureUserDocument(AuthUser user) async {}
}

FreshnessSnapshot _freshness(DateTime serverTime) {
  return FreshnessSnapshot(
    serverTime: serverTime,
    sections: const {'groups': FreshnessSection(changed: false)},
  );
}

FreshnessSnapshot _familyFreshness(DateTime serverTime) {
  return FreshnessSnapshot(
    serverTime: serverTime,
    sections: const {
      'groups': FreshnessSection(changed: false),
      'plans': FreshnessSection(changed: false),
    },
  );
}

void main() {
  const splitGroup = GroupSummary(
    id: 'split-1',
    name: 'Trip to Goa',
    groupType: GroupType.split,
    memberCount: 4,
  );
  const familyGroup = GroupSummary(
    id: 'family-1',
    name: 'Rao family',
    groupType: GroupType.family,
    memberCount: 4,
  );
  const pendingFamilyGroup = GroupSummary(
    id: 'family-pending-1',
    name: 'Rao household',
    groupType: GroupType.family,
    memberCount: 1,
    pendingInviteCount: 1,
    pendingInvites: [
      GroupPendingInvite(
        contact: 'nisha@example.com',
        emailNormalized: 'nisha@example.com',
        role: 'Wife',
      ),
    ],
  );

  testWidgets('groups page shows only split groups', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupsPage(
            repository: _FakeGroupsRepository([splitGroup, familyGroup]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trip to Goa'), findsOneWidget);
    expect(find.text('Rao family'), findsNothing);
  });

  testWidgets('groups auto-refresh skips reload when freshness is unchanged', (
    tester,
  ) async {
    final repository = _FakeGroupsRepository([splitGroup]);
    final freshnessRepository = _FakeFreshnessRepository([
      _freshness(DateTime.parse('2026-06-07T10:00:00Z')),
      _freshness(DateTime.parse('2026-06-07T10:00:45Z')),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupsPage(
            repository: repository,
            freshnessRepository: freshnessRepository,
            autoRefresh: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 45));
    await tester.pump();

    expect(repository.fetchGroupCount, 1);
    expect(freshnessRepository.requests, hasLength(2));
    expect(freshnessRepository.requests.last.sections, ['groups']);
    expect(
      freshnessRepository.requests.last.since,
      DateTime.parse('2026-06-07T10:00:00Z'),
    );
  });

  testWidgets('family auto-refresh skips reload when freshness is unchanged', (
    tester,
  ) async {
    final repository = _FakeGroupsRepository([familyGroup]);
    final freshnessRepository = _FakeFreshnessRepository([
      _familyFreshness(DateTime.parse('2026-06-07T10:00:00Z')),
      _familyFreshness(DateTime.parse('2026-06-07T10:00:45Z')),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FamilyPage(
            repository: repository,
            freshnessRepository: freshnessRepository,
            monthlyPlanRepository: _FakeMonthlyPlanRepository(),
            autoRefresh: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 45));
    await tester.pump();

    expect(repository.fetchGroupCount, 1);
    expect(freshnessRepository.requests, hasLength(2));
    expect(freshnessRepository.requests.last.sections, ['groups', 'plans']);
    expect(
      freshnessRepository.requests.last.since,
      DateTime.parse('2026-06-07T10:00:00Z'),
    );
  });

  testWidgets('family page shows only family groups', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FamilyPage(
            repository: _FakeGroupsRepository([splitGroup, familyGroup]),
            monthlyPlanRepository: _FakeMonthlyPlanRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rao family'), findsOneWidget);
    expect(find.text('Trip to Goa'), findsNothing);
    expect(find.textContaining('Wife', skipOffstage: false), findsOneWidget);
    expect(find.text('Groceries'), findsWidgets);
  });

  testWidgets('family page surfaces pending household invites', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FamilyPage(
            repository: _FakeGroupsRepository([pendingFamilyGroup]),
            monthlyPlanRepository: _FakeMonthlyPlanRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rao household'), findsOneWidget);
    expect(find.text('1 active · 1 pending'), findsOneWidget);
    expect(find.text('Pending invites', skipOffstage: false), findsOneWidget);
    expect(
      find.text('nisha@example.com · Wife', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('family page surfaces household settle up suggestion', (
    tester,
  ) async {
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: _FakeUserProfileRepository(),
    );
    addTearDown(authCubit.close);
    final repository = _FakeGroupsRepository(
      [familyGroup],
      members: const [
        GroupMember(
          uid: 'member-1',
          displayName: 'Nisha',
          email: 'nisha@example.com',
          phone: '',
          role: 'Wife',
        ),
        GroupMember(
          uid: 'member-2',
          displayName: 'Sushrut',
          email: 'sushrut@example.com',
          phone: '',
          role: 'Husband',
        ),
      ],
      expenses: [
        GroupExpense(
          id: 'household-expense-1',
          groupId: familyGroup.id,
          createdBy: 'member-1',
          updatedBy: 'member-1',
          paidBy: 'member-1',
          splitMode: 'equally',
          splitWith: const ['member-1', 'member-2'],
          amount: 1200,
          category: 'Groceries',
          description: 'Monthly grocery run',
          attachments: const [],
          date: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
    );

    await tester.pumpWidget(
      BlocProvider.value(
        value: authCubit,
        child: MaterialApp(
          home: Scaffold(
            body: FamilyPage(
              repository: repository,
              monthlyPlanRepository: _FakeMonthlyPlanRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settle up'), findsOneWidget);
    expect(find.text('Sushrut pays Nisha ₹600.00'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Settle'));
    await tester.pumpAndSettle();

    expect(find.text('Group settings'), findsOneWidget);
    expect(find.text('Sushrut'), findsWidgets);
  });

  testWidgets('group expense dialog offers bill scan and purchase date', (
    tester,
  ) async {
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: _FakeUserProfileRepository(),
    );
    addTearDown(authCubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: authCubit,
        child: MaterialApp(
          home: GroupDetailsPage(
            group: familyGroup,
            repository: _FakeGroupsRepository([familyGroup]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settle up'), findsOneWidget);

    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();

    expect(find.text('Add household expense'), findsOneWidget);
    expect(find.text('Scan bill'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    expect(find.text('Monthly category'), findsOneWidget);
  });

  testWidgets('group settle up dialog defaults to active balance currency', (
    tester,
  ) async {
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: _FakeUserProfileRepository(),
    );
    addTearDown(authCubit.close);
    final repository = _FakeGroupsRepository(
      [familyGroup],
      members: const [
        GroupMember(
          uid: 'member-1',
          displayName: 'Nisha',
          email: 'nisha@example.com',
          phone: '',
          role: 'Wife',
        ),
        GroupMember(
          uid: 'member-2',
          displayName: 'Sushrut',
          email: 'sushrut@example.com',
          phone: '',
          role: 'Husband',
        ),
      ],
      expenses: [
        GroupExpense(
          id: 'expense-usd',
          groupId: familyGroup.id,
          createdBy: 'member-1',
          updatedBy: 'member-1',
          paidBy: 'member-1',
          splitMode: 'equally',
          splitWith: const ['member-1', 'member-2'],
          amount: 120,
          currency: 'USD',
          convertedAmounts: const {'USD': 120, 'NOK': 1300},
          category: 'Travel',
          description: 'Airport dinner',
          attachments: const [],
          date: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
    );

    await tester.pumpWidget(
      BlocProvider.value(
        value: authCubit,
        child: MaterialApp(
          home: GroupDetailsPage(group: familyGroup, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settle up'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settle up'));
    await tester.pumpAndSettle();

    expect(find.text('Settle up with Sushrut'), findsOneWidget);
    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('NOK'), findsWidgets);

    await tester.enterText(find.byType(TextFormField).last, '650');
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();

    expect(repository.recordedGroupSettlement?.groupId, familyGroup.id);
    expect(repository.recordedGroupSettlement?.memberUid, 'member-2');
    expect(repository.recordedGroupSettlement?.direction, 'paid');
    expect(repository.recordedGroupSettlement?.amount, 650);
    expect(repository.recordedGroupSettlement?.currency, 'NOK');
    expect(find.text('Nisha paid Sushrut'), findsOneWidget);
  });

  testWidgets('family page opens grocery expense form from household card', (
    tester,
  ) async {
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: _FakeUserProfileRepository(),
    );
    addTearDown(authCubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: authCubit,
        child: MaterialApp(
          home: Scaffold(
            body: FamilyPage(
              repository: _FakeGroupsRepository(
                [familyGroup],
                expenses: [
                  _groupExpense(
                    id: 'expense-clean',
                    description: 'Monthly grocery run',
                    amount: 1200,
                    category: 'Groceries',
                    attachments: const ['https://example.com/receipt.jpg'],
                    date: DateTime.now(),
                  ),
                ],
              ),
              monthlyPlanRepository: _FakeMonthlyPlanRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add groceries'));
    await tester.pumpAndSettle();

    expect(find.text('Add household expense'), findsOneWidget);
    expect(find.text('Monthly category'), findsOneWidget);
    final descriptionField = tester.widget<TextField>(
      _textFieldWithLabel('Description'),
    );
    expect(descriptionField.controller?.text, 'Groceries');
  });

  testWidgets('family page opens household expense from plan category', (
    tester,
  ) async {
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: _FakeUserProfileRepository(),
    );
    addTearDown(authCubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: authCubit,
        child: MaterialApp(
          home: Scaffold(
            body: FamilyPage(
              repository: _FakeGroupsRepository(
                [familyGroup],
                expenses: [
                  _groupExpense(
                    id: 'expense-clean-plan',
                    description: 'Monthly grocery run',
                    amount: 1200,
                    category: 'Groceries',
                    attachments: const ['https://example.com/receipt.jpg'],
                    date: DateTime.now(),
                  ),
                ],
              ),
              monthlyPlanRepository: _FakeMonthlyPlanRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byTooltip('Add Groceries expense'),
      120,
    );
    await tester.tap(find.byTooltip('Add Groceries expense'));
    await tester.pumpAndSettle();

    expect(find.text('Add household expense'), findsOneWidget);
    expect(find.text('Monthly category'), findsOneWidget);
    final descriptionField = tester.widget<TextField>(
      _textFieldWithLabel('Description'),
    );
    expect(descriptionField.controller?.text, 'Groceries');
  });

  testWidgets('group details filters expense review list', (tester) async {
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: _FakeUserProfileRepository(),
    );
    addTearDown(authCubit.close);
    final today = DateTime.now();
    final repository = _FakeGroupsRepository(
      [familyGroup],
      expenses: [
        _groupExpense(
          id: 'expense-groceries',
          description: 'Weekly groceries',
          amount: 82,
          currency: 'USD',
          category: 'Groceries',
          date: today,
        ),
        _groupExpense(
          id: 'expense-internet',
          description: 'Internet bill',
          amount: 1200,
          currency: 'INR',
          category: 'Utilities',
          attachments: const ['https://example.com/bill.jpg'],
          date: today,
        ),
      ],
    );

    await tester.pumpWidget(
      BlocProvider.value(
        value: authCubit,
        child: MaterialApp(
          home: GroupDetailsPage(group: familyGroup, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_textFieldWithLabel('Search expenses'), 'weekly');
    await tester.pumpAndSettle();

    expect(find.text('Weekly groceries'), findsOneWidget);
    expect(find.text('Internet bill'), findsNothing);
    expect(find.text('Missing receipt'), findsWidgets);
    expect(find.text('1 match'), findsOneWidget);

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

  testWidgets('family review intent opens filtered household expenses', (
    tester,
  ) async {
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: _FakeUserProfileRepository(),
    );
    addTearDown(authCubit.close);
    final today = DateTime.now();
    final repository = _FakeGroupsRepository(
      [familyGroup],
      expenses: [
        _groupExpense(
          id: 'expense-groceries',
          description: 'Monthly grocery run',
          amount: 1200,
          category: 'Groceries',
          date: today,
        ),
        _groupExpense(
          id: 'expense-school',
          description: 'School books',
          amount: 700,
          category: 'School and kids',
          date: today,
        ),
      ],
    );

    await tester.pumpWidget(
      BlocProvider.value(
        value: authCubit,
        child: MaterialApp(
          home: Scaffold(
            body: FamilyPage(
              repository: repository,
              monthlyPlanRepository: _FakeMonthlyPlanRepository(),
              openReviewOnLaunch: true,
              initialReviewFilter: const GroupExpenseReviewFilter(
                category: 'Groceries',
                currentMonthOnly: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rao family'), findsWidgets);
    expect(find.text('Search expenses'), findsOneWidget);
    expect(find.text('Monthly grocery run'), findsOneWidget);
    expect(find.text('School books'), findsNothing);
    expect(find.text('1 match'), findsOneWidget);
  });

  testWidgets('family audit shortcut opens uncategorized review', (
    tester,
  ) async {
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: _FakeUserProfileRepository(),
    );
    addTearDown(authCubit.close);
    final today = DateTime.now();
    final repository = _FakeGroupsRepository(
      [familyGroup],
      expenses: [
        _groupExpense(
          id: 'expense-groceries',
          description: 'Monthly grocery run',
          amount: 1200,
          category: 'Groceries',
          attachments: const [],
          date: today,
        ),
        _groupExpense(
          id: 'expense-mystery',
          description: 'Mystery item',
          amount: 300,
          category: '',
          attachments: const ['https://example.com/receipt.jpg'],
          date: today,
        ),
        _groupExpense(
          id: 'expense-other',
          description: 'Explicit other',
          amount: 200,
          category: 'Other',
          attachments: const ['https://example.com/other.jpg'],
          date: today,
        ),
      ],
    );

    await tester.pumpWidget(
      BlocProvider.value(
        value: authCubit,
        child: MaterialApp(
          home: Scaffold(
            body: FamilyPage(
              repository: repository,
              monthlyPlanRepository: _FakeMonthlyPlanRepository(
                excludedExpenseCount: 1,
                excludedActualsByCurrency: const {'USD': 12},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review needed'), findsOneWidget);
    expect(find.text('Missing receipts'), findsOneWidget);
    expect(find.text('Uncategorized'), findsOneWidget);
    expect(find.text('Outside INR plan'), findsOneWidget);

    await tester.tap(find.text('Uncategorized').first);
    await tester.pumpAndSettle();

    expect(find.text('Search expenses'), findsOneWidget);
    final uncategorizedChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Uncategorized'),
    );
    expect(uncategorizedChip.selected, isTrue);
    expect(find.text('Mystery item'), findsOneWidget);
    expect(find.text('Explicit other'), findsNothing);
    expect(find.text('Monthly grocery run'), findsNothing);
    expect(find.text('1 match'), findsOneWidget);
  });

  testWidgets('family audit shortcut opens outside plan currency review', (
    tester,
  ) async {
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: _FakeUserProfileRepository(),
    );
    addTearDown(authCubit.close);
    final today = DateTime.now();
    final repository = _FakeGroupsRepository(
      [familyGroup],
      expenses: [
        _groupExpense(
          id: 'expense-imported',
          description: 'Imported groceries',
          amount: 12,
          currency: 'USD',
          category: 'Groceries',
          attachments: const ['https://example.com/imported.jpg'],
          date: today,
        ),
        _groupExpense(
          id: 'expense-internet',
          description: 'Internet bill',
          amount: 1200,
          currency: 'INR',
          category: 'Utilities',
          attachments: const ['https://example.com/bill.jpg'],
          date: today,
        ),
      ],
    );

    await tester.pumpWidget(
      BlocProvider.value(
        value: authCubit,
        child: MaterialApp(
          home: Scaffold(
            body: FamilyPage(
              repository: repository,
              monthlyPlanRepository: _FakeMonthlyPlanRepository(
                excludedExpenseCount: 1,
                excludedActualsByCurrency: const {'USD': 12},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Outside INR plan'));
    await tester.pumpAndSettle();

    expect(find.text('Search expenses'), findsOneWidget);
    expect(find.text('Missing INR conversion'), findsWidgets);
    expect(find.text('Imported groceries'), findsOneWidget);
    expect(find.text('Internet bill'), findsNothing);
    expect(find.text('1 match'), findsOneWidget);
  });

  testWidgets('family quick-add launch auto-opens only one household', (
    tester,
  ) async {
    final authCubit = AuthCubit(
      repository: _FakeAuthRepository(),
      userProfileRepository: _FakeUserProfileRepository(),
    );
    addTearDown(authCubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: authCubit,
        child: MaterialApp(
          home: Scaffold(
            body: FamilyPage(
              repository: _FakeGroupsRepository([familyGroup]),
              monthlyPlanRepository: _FakeMonthlyPlanRepository(),
              openAddExpenseOnLaunch: true,
              initialExpenseCategory: 'Groceries',
              initialExpenseDescription: 'Groceries',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add household expense'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(_textFieldWithLabel('Description'))
          .controller
          ?.text,
      'Groceries',
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      BlocProvider.value(
        value: authCubit,
        child: MaterialApp(
          home: Scaffold(
            body: FamilyPage(
              key: const ValueKey('two-household-family-page'),
              repository: _FakeGroupsRepository([
                familyGroup,
                const GroupSummary(
                  id: 'family-2',
                  name: 'Parents household',
                  groupType: GroupType.family,
                  memberCount: 2,
                ),
              ]),
              monthlyPlanRepository: _FakeMonthlyPlanRepository(),
              openAddExpenseOnLaunch: true,
              initialExpenseCategory: 'Groceries',
              initialExpenseDescription: 'Groceries',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add household expense'), findsNothing);
    expect(find.text('Rao family'), findsWidgets);
    expect(find.text('Choose household for groceries'), findsOneWidget);
    expect(find.text('Add here'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Parents household'), 120);
    expect(find.text('Parents household'), findsOneWidget);
    await tester.tap(find.text('Parents household'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add here'));
    await tester.tap(find.text('Add here'));
    await tester.pumpAndSettle();

    expect(find.text('Add household expense'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(_textFieldWithLabel('Description'))
          .controller
          ?.text,
      'Groceries',
    );
  });
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

GroupExpense _groupExpense({
  required String id,
  required String description,
  required double amount,
  required DateTime date,
  String groupId = 'family-1',
  String currency = 'INR',
  String category = '',
  Map<String, double> convertedAmounts = const {},
  List<String> attachments = const [],
}) {
  return GroupExpense(
    id: id,
    groupId: groupId,
    createdBy: 'member-1',
    updatedBy: 'member-1',
    paidBy: 'member-1',
    splitMode: 'equally',
    splitWith: const ['member-1'],
    amount: amount,
    currency: currency,
    convertedAmounts: convertedAmounts,
    category: category,
    description: description,
    attachments: attachments,
    date: date,
    createdAt: date,
    updatedAt: date,
  );
}
