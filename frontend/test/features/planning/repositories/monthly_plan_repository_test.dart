import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeAuthTokenProvider implements AuthTokenProvider {
  const _FakeAuthTokenProvider();

  @override
  Future<String> getBearerToken() async => 'session-token';
}

void main() {
  test('fetches and saves household-scoped monthly plans', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.headers['authorization'], 'Bearer session-token');
      if (request.method == 'GET') {
        expect(request.url.path.endsWith('/api/v1/planning/monthly'), isTrue);
        expect(request.url.queryParameters['month'], '2026-06');
        expect(request.url.queryParameters['groupId'], 'family-1');
        return http.Response(
          '{"month":"2026-06","groupId":"family-1","currency":"USD","totalBudget":500,"totalActual":125,"totalRemaining":375,"actualsMetadata":{"uncountedExpenseCount":2,"uncountedSpendByCurrency":{"EUR":12}},"categories":[]}',
          200,
        );
      }
      if (request.method == 'PUT') {
        expect(request.body, contains('"groupId":"family-1"'));
        expect(request.body, contains('"currency":"USD"'));
        expect(request.body, contains('"Groceries":500'));
        return http.Response(
          '{"month":"2026-06","groupId":"family-1","currency":"USD","totalBudget":500,"totalActual":125,"totalRemaining":375,"skippedActualExpenseCount":1,"excludedActualsByCurrency":{"NOK":45},"categories":[]}',
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final repository = MonthlyPlanRepository(
      client: client,
      authTokenProvider: const _FakeAuthTokenProvider(),
    );

    final fetched = await repository.fetchPlan(
      month: '2026-06',
      groupId: 'family-1',
    );
    final saved = await repository.savePlan(
      month: '2026-06',
      groupId: 'family-1',
      currency: 'USD',
      budgets: {'Groceries': 500},
    );

    expect(fetched.groupId, 'family-1');
    expect(fetched.excludedExpenseCount, 2);
    expect(fetched.excludedActualsByCurrency, {'EUR': 12});
    expect(saved.groupId, 'family-1');
    expect(saved.currency, 'USD');
    expect(saved.excludedExpenseCount, 1);
    expect(saved.excludedActualsByCurrency, {'NOK': 45});
    expect(requests, hasLength(2));
  });
}
