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
}
