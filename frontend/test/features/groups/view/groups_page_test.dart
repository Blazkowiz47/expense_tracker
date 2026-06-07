import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/family/view/family_page.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_member.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:expense_tracker/features/groups/view/groups_page.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:flutter/material.dart';
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
}
