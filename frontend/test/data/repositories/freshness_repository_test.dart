import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/data/repositories/freshness_repository.dart';
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
  test('fetchFreshness sends cursor and parses tombstones', () async {
    final since = DateTime.parse('2026-06-07T10:00:00Z');
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/sync/freshness');
      expect(request.url.queryParameters['since'], since.toIso8601String());
      expect(request.url.queryParameters['sections'], 'activity,groups');
      expect(request.headers['authorization'], 'Bearer session-token');
      return http.Response('''
        {
          "serverTime": "2026-06-07T10:00:45Z",
          "sections": {
            "activity": {
              "changed": true,
              "watermark": "2026-06-07T10:00:40Z",
              "personalDeletedIds": ["expense-1"],
              "groupDeleted": [
                {"groupId": "group-1", "expenseId": "group-expense-1"}
              ]
            },
            "groups": {
              "changed": false,
              "watermark": "2026-06-07T09:59:00Z",
              "deletedGroupIds": ["group-2"]
            }
          }
        }
        ''', 200);
    });

    final repository = FreshnessRepository(
      client: client,
      authTokenProvider: const _FakeAuthTokenProvider('session-token'),
    );

    final snapshot = await repository.fetchFreshness(
      since: since,
      sections: const ['activity', 'groups'],
    );

    expect(snapshot.serverTime, DateTime.parse('2026-06-07T10:00:45Z'));
    final activity = snapshot.sections['activity']!;
    expect(activity.changed, isTrue);
    expect(activity.personalDeletedIds, ['expense-1']);
    expect(activity.groupDeleted.single.groupId, 'group-1');
    expect(activity.groupDeleted.single.expenseId, 'group-expense-1');
    expect(snapshot.sections['groups']!.changed, isFalse);
    expect(snapshot.sections['groups']!.deletedGroupIds, ['group-2']);
  });
}
