import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/activity/repositories/activity_feed_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeAuthTokenProvider implements AuthTokenProvider {
  const _FakeAuthTokenProvider(this.token);

  final String token;

  @override
  Future<String> getBearerToken() async => token;
}

void main() {
  test('fetchActivity sends cursor and parses mixed entries', () async {
    final since = DateTime.parse('2026-06-07T10:00:00Z');
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/activity');
      expect(request.url.queryParameters['since'], since.toIso8601String());
      expect(request.url.queryParameters['limit'], '40');
      expect(request.url.queryParameters['include'], 'personal,group');
      expect(request.headers['authorization'], 'Bearer session-token');
      return http.Response('''
        {
          "serverTime": "2026-06-07T10:00:45Z",
          "entries": [
            {
              "kind": "personalExpense",
              "id": "expense-1",
              "date": "2026-06-07T09:00:00Z",
              "updatedAt": "2026-06-07T10:00:10Z",
              "expense": {
                "id": "expense-1",
                "amount": 42.5,
                "currency": "NOK",
                "category": "Coffee",
                "description": "Morning coffee",
                "paymentMethod": "card",
                "date": "2026-06-07T09:00:00Z",
                "createdAt": "2026-06-07T09:00:00Z",
                "updatedAt": "2026-06-07T10:00:10Z"
              }
            },
            {
              "kind": "groupExpense",
              "id": "group-expense-1",
              "groupId": "group-1",
              "date": "2026-06-07T08:30:00Z",
              "updatedAt": "2026-06-07T10:00:15Z",
              "group": {
                "id": "group-1",
                "name": "Household",
                "groupType": "family",
                "memberCount": 2
              },
              "expense": {
                "id": "group-expense-1",
                "groupId": "group-1",
                "createdBy": "alice",
                "updatedBy": "alice",
                "paidBy": "alice",
                "splitMode": "equally",
                "splitWith": ["alice", "bob"],
                "amount": 120,
                "currency": "INR",
                "convertedAmounts": {"INR": 120},
                "category": "Groceries",
                "description": "Weekly groceries",
                "attachments": [],
                "date": "2026-06-07T08:30:00Z",
                "createdAt": "2026-06-07T08:30:00Z",
                "updatedAt": "2026-06-07T10:00:15Z"
              }
            }
          ],
          "tombstones": {
            "personalDeletedIds": ["expense-2"],
            "deletedGroupIds": ["group-2"],
            "groupDeleted": [
              {"groupId": "group-1", "expenseId": "group-expense-2"}
            ]
          }
        }
        ''', 200);
    });

    final repository = ActivityFeedRepository(
      client: client,
      authTokenProvider: const _FakeAuthTokenProvider('session-token'),
    );

    final feed = await repository.fetchActivity(since: since, limit: 40);

    expect(feed.serverTime, DateTime.parse('2026-06-07T10:00:45Z'));
    expect(feed.entries, hasLength(2));
    expect(feed.entries.first.personalExpense?.title, 'Morning coffee');
    expect(feed.entries.last.group?.groupType, GroupType.family);
    expect(feed.entries.last.groupExpense?.description, 'Weekly groceries');
    expect(feed.tombstones.personalDeletedIds, ['expense-2']);
    expect(feed.tombstones.deletedGroupIds, ['group-2']);
    expect(feed.tombstones.groupDeleted.single.expenseId, 'group-expense-2');
  });
}
