import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/features/recurring/repositories/api_recurring_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeAuthTokenProvider implements AuthTokenProvider {
  const _FakeAuthTokenProvider();

  @override
  Future<String> getBearerToken() async => 'session-token';
}

void main() {
  test('creates income templates and confirms actual occurrence amounts', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/api/v1/recurring/templates') &&
          request.method == 'POST') {
        expect(request.headers['authorization'], 'Bearer session-token');
        expect(request.body, contains('"kind":"income"'));
        expect(request.body, contains('"currency":"USD"'));
        expect(request.body, contains('"frequency":"weekly"'));
        expect(request.body, contains('"dayOfMonth":15'));
        return http.Response(
          '{"id":"template-1","title":"Salary","kind":"income","expectedAmount":31000,"currency":"USD","category":"Salary","frequency":"weekly","dayOfMonth":15,"startDate":"2026-05-15T00:00:00Z","nextDueDate":"2026-05-15T00:00:00Z","active":true}',
          201,
        );
      }
      if (request.url.path.endsWith('/api/v1/recurring/occurrences') &&
          request.method == 'GET') {
        expect(request.url.queryParameters['month'], '2026-05');
        return http.Response(
          '{"occurrences":[{"id":"occ-1","templateId":"template-1","period":"2026-05","kind":"income","title":"Salary","category":"Salary","currency":"INR","expectedAmount":31000,"actualAmount":null,"dueDate":"2026-05-15T00:00:00Z","actualDate":null,"status":"expected"}]}',
          200,
        );
      }
      if (request.url.path.endsWith(
            '/api/v1/recurring/occurrences/occ-1/confirm',
          ) &&
          request.method == 'POST') {
        expect(request.body, contains('"actualAmount":30500'));
        return http.Response(
          '{"id":"occ-1","templateId":"template-1","period":"2026-05","kind":"income","title":"Salary","category":"Salary","currency":"INR","expectedAmount":31000,"actualAmount":30500,"dueDate":"2026-05-15T00:00:00Z","actualDate":"2026-05-16T10:00:00Z","status":"confirmed"}',
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final repository = ApiRecurringRepository(
      client: client,
      authTokenProvider: const _FakeAuthTokenProvider(),
    );

    final template = await repository.createTemplate(
      title: 'Salary',
      kind: 'income',
      amount: 31000,
      category: 'Salary',
      currency: 'USD',
      frequency: 'weekly',
      dayOfMonth: 15,
      startDate: DateTime.utc(2026, 5, 15),
    );
    final occurrences = await repository.fetchOccurrences(month: '2026-05');
    final confirmed = await repository.confirmOccurrence(
      occurrenceId: 'occ-1',
      actualAmount: 30500,
      actualDate: DateTime.utc(2026, 5, 16, 10),
    );

    expect(template.kind, 'income');
    expect(template.currency, 'USD');
    expect(template.frequency, 'weekly');
    expect(occurrences.single.expectedAmount, 31000);
    expect(confirmed.isConfirmed, isTrue);
    expect(confirmed.actualAmount, 30500);
    expect(requests, hasLength(3));
  });
}
