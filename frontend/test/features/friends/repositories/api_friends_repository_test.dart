import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/features/friends/repositories/api_friends_repository.dart';
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
  test('fetches and maps friends list', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/v1/friends')) {
        expect(request.headers['authorization'], 'Bearer dev-token');
        return http.Response(
          '{"friends":[{"uid":"u2","displayName":"Alice","email":"alice@example.com"}]}',
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final repository = ApiFriendsRepository(
      client: client,
      authTokenProvider: const _FakeAuthTokenProvider('dev-token'),
    );
    final friends = await repository.fetchFriends();

    expect(friends.length, 1);
    expect(friends.first.uid, 'u2');
    expect(friends.first.displayName, 'Alice');
  });

  test('fetches settlements and updates paid date', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.headers['authorization'], 'Bearer dev-token');
      if (request.method == 'GET' &&
          request.url.path.endsWith('/api/v1/friends/settlements')) {
        expect(request.url.queryParameters['friendUid'], 'u2');
        return http.Response(
          jsonEncode({
            'settlements': [
              {
                'id': 'settlement-1',
                'uids': ['u1', 'u2'],
                'payerUid': 'u1',
                'receiverUid': 'u2',
                'amount': 120,
                'currency': 'INR',
                'date': '2026-06-05T00:00:00Z',
                'createdAt': '2026-06-07T00:00:00Z',
              },
            ],
          }),
          200,
        );
      }
      if (request.method == 'PUT' &&
          request.url.path.endsWith(
            '/api/v1/friends/settlements/settlement-1',
          )) {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['date'], '2026-06-01T00:00:00.000Z');
        return http.Response(
          jsonEncode({
            'id': 'settlement-1',
            'uids': ['u1', 'u2'],
            'payerUid': 'u1',
            'receiverUid': 'u2',
            'amount': 120,
            'currency': 'INR',
            'date': payload['date'],
            'createdAt': '2026-06-07T00:00:00Z',
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final repository = ApiFriendsRepository(
      client: client,
      authTokenProvider: const _FakeAuthTokenProvider('dev-token'),
    );

    final settlements = await repository.fetchSettlements(friendUid: 'u2');
    final updated = await repository.updateSettlementDate(
      settlementId: settlements.single.id,
      date: DateTime(2026, 6),
    );

    expect(requests, hasLength(2));
    expect(settlements.single.date.day, 5);
    expect(updated.date.day, 1);
  });
}
