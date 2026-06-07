import 'package:expense_tracker/data/models/group.dart';
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
  Future<List<GroupSummary>> fetchGroups() async => groups;

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

class _FakeMonthlyPlanRepository extends MonthlyPlanRepository {
  _FakeMonthlyPlanRepository()
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  @override
  Future<MonthlyPlan> fetchPlan({
    required String month,
    String? groupId,
  }) async {
    return const MonthlyPlan(
      month: '2026-06',
      currency: 'INR',
      totalBudget: 5000,
      totalActual: 1200,
      totalRemaining: 3800,
      categories: [
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
    expect(find.textContaining('Wife'), findsOneWidget);
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
    expect(find.text('Pending invites'), findsOneWidget);
    expect(find.text('nisha@example.com · Wife'), findsOneWidget);
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
              repository: _FakeGroupsRepository([familyGroup]),
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
      find.byType(TextField).first,
    );
    expect(descriptionField.controller?.text, 'Groceries');
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
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
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
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(find.text('Parents household'), findsOneWidget);
    await tester.tap(find.text('Parents household'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add here'));
    await tester.tap(find.text('Add here'));
    await tester.pumpAndSettle();

    expect(find.text('Add household expense'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'Groceries',
    );
  });
}
