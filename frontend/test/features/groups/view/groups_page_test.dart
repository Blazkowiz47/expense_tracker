import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/family/view/family_page.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_member.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:expense_tracker/features/groups/view/groups_page.dart';
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
    ),
  ];

  @override
  Future<List<GroupExpense>> fetchExpenses(String groupId) async => const [];
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rao family'), findsOneWidget);
    expect(find.text('Trip to Goa'), findsNothing);
  });
}
