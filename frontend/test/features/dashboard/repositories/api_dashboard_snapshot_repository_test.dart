import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/features/dashboard/repositories/api_dashboard_snapshot_repository.dart';
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
  test('maps backend snapshot payload into dashboard snapshot', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/v1/dashboard/snapshot')) {
        expect(request.headers['authorization'], 'Bearer session-token');
        expect(request.url.queryParameters['includeAi'], 'false');
        return http.Response(
          '{"overallLabel":"Overall, you are owed","overallAmountText":"INR 113.33","overallPositive":true,"friendItems":[{"title":"Groceries","subtitle":"category total","amountText":"INR 100.00","positive":true}],"groupItems":[{"title":"Groceries","subtitle":"category total","amountText":"INR 100.00","positive":true}],"actionItems":[{"title":"Confirm rent","subtitle":"Due today - INR 12000.00","severity":"info","destination":"recurring","actionType":"confirm_recurring","occurrenceId":"occ-1","period":"2026-05"}],"activityItems":[{"title":"Groceries 1","subtitle":"2026-02-24T11:00:00Z","amountText":"You owe INR 50.00","positive":false}],"accountName":"Local User","accountEmail":"uid-1@local"}',
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final repository = ApiDashboardSnapshotRepository(
      client: client,
      authTokenProvider: const _FakeAuthTokenProvider('session-token'),
    );
    final snapshot = await repository.fetchSnapshot();

    expect(snapshot.overallLabel, 'Overall, you are owed');
    expect(snapshot.overallAmountText, 'INR 113.33');
    expect(snapshot.groupItems.first.title, 'Groceries');
    expect(snapshot.actionItems.first.destination, 'recurring');
    expect(snapshot.actionItems.first.actionType, 'confirm_recurring');
    expect(snapshot.actionItems.first.occurrenceId, 'occ-1');
    expect(snapshot.actionItems.first.period, '2026-05');
    expect(snapshot.activityItems.first.title, 'Groceries 1');
  });

  test('fetches dashboard AI insights separately', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/v1/dashboard/ai-insights')) {
        expect(request.headers['authorization'], 'Bearer session-token');
        return http.Response(
          '{"aiInsights":[{"label":"AI summary","message":"Looks good.","tone":"positive","actions":[]}]}',
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final repository = ApiDashboardSnapshotRepository(
      client: client,
      authTokenProvider: const _FakeAuthTokenProvider('session-token'),
    );
    final insights = await repository.fetchAiInsights();

    expect(insights, hasLength(1));
    expect(insights.first.label, 'AI summary');
    expect(insights.first.message, 'Looks good.');
  });
}
