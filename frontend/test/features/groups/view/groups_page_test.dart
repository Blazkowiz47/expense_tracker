import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/family/view/family_page.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_member.dart';
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
  _FakeGroupsRepository(this.groups)
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  final List<GroupSummary> groups;

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
  Future<List<GroupMember>> fetchMembers(String groupId) async => const [
    GroupMember(
      uid: 'member-1',
      displayName: 'Nisha',
      email: 'nisha@example.com',
      phone: '',
      role: 'Wife',
    ),
  ];

  @override
  Future<List<GroupExpense>> fetchExpenses(String groupId) async => [
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
}

class _FakeMonthlyPlanRepository extends MonthlyPlanRepository {
  _FakeMonthlyPlanRepository()
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  @override
  Future<MonthlyPlan> fetchPlan({required String month}) async {
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

    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();

    expect(find.text('Add household expense'), findsOneWidget);
    expect(find.text('Scan bill'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    expect(find.text('Monthly category'), findsOneWidget);
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
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(find.text('Parents household'), findsOneWidget);
  });
}
