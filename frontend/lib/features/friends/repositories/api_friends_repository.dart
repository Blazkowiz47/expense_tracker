import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/core/utils/backend_date_codec.dart';
import 'package:expense_tracker/features/friends/models/friend_contact.dart';
import 'package:expense_tracker/features/friends/models/friend_settlement.dart';
import 'package:http/http.dart' as http;

class ApiFriendsRepository {
  ApiFriendsRepository({
    required http.Client client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client,
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;

  Future<List<FriendContact>> fetchFriends() async {
    final response = await _request(method: 'GET', path: '/api/v1/friends');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawFriends = (payload['friends'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    return rawFriends.map(FriendContact.fromJson).toList(growable: false);
  }

  Future<FriendResolveResult> resolveFriend(String emailOrPhone) async {
    final response = await _request(
      method: 'POST',
      path: '/api/v1/friends/resolve',
      body: <String, dynamic>{'emailOrPhone': emailOrPhone},
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return FriendResolveResult.fromJson(payload);
  }

  Future<void> addFriend(String emailOrPhone) async {
    await _request(
      method: 'POST',
      path: '/api/v1/friends/add',
      body: <String, dynamic>{'emailOrPhone': emailOrPhone},
    );
  }

  Future<void> removeFriend(String emailOrPhone) async {
    await _request(
      method: 'POST',
      path: '/api/v1/friends/remove',
      body: <String, dynamic>{'emailOrPhone': emailOrPhone},
    );
  }

  Future<Map<String, Map<String, double>>> fetchBalances() async {
    final response = await _request(
      method: 'GET',
      path: '/api/v1/friends/balances',
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawByCurrency =
        payload['balancesByCurrency'] as Map<String, dynamic>? ?? const {};
    if (rawByCurrency.isNotEmpty) {
      return rawByCurrency.map((key, value) {
        final rawAmounts = value as Map<String, dynamic>? ?? const {};
        return MapEntry(
          key,
          rawAmounts.map(
            (currency, amount) =>
                MapEntry(currency, (amount as num?)?.toDouble() ?? 0),
          ),
        );
      });
    }
    final rawBalances =
        payload['balances'] as Map<String, dynamic>? ?? const {};
    return rawBalances.map(
      (key, value) => MapEntry(key, {'INR': (value as num?)?.toDouble() ?? 0}),
    );
  }

  Future<List<FriendSettlement>> fetchSettlements({
    String friendUid = '',
  }) async {
    final query = friendUid.trim().isEmpty
        ? ''
        : '?friendUid=${Uri.encodeQueryComponent(friendUid.trim())}';
    final response = await _request(
      method: 'GET',
      path: '/api/v1/friends/settlements$query',
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawSettlements =
        (payload['settlements'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>();
    return rawSettlements
        .map(FriendSettlement.fromJson)
        .toList(growable: false);
  }

  Future<void> recordSettlement({
    required String friendUid,
    required String direction,
    required double amount,
    String currency = 'INR',
    DateTime? date,
  }) async {
    await _request(
      method: 'POST',
      path: '/api/v1/friends/settlements',
      body: <String, dynamic>{
        'friendUid': friendUid,
        'direction': direction,
        'amount': amount,
        'currency': currency,
        if (date != null) 'date': BackendDateCodec.encodeDate(date),
      },
    );
  }

  Future<FriendSettlement> updateSettlementDate({
    required String settlementId,
    required DateTime date,
  }) async {
    final response = await _request(
      method: 'PUT',
      path: '/api/v1/friends/settlements/$settlementId',
      body: <String, dynamic>{'date': BackendDateCodec.encodeDate(date)},
    );
    return FriendSettlement.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<http.Response> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    final request = switch (method) {
      'GET' => _client.get(uri, headers: headers),
      'POST' => _client.post(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      ),
      'PUT' => _client.put(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      ),
      _ => throw UnsupportedError('Unsupported method $method'),
    };

    final response = await request.timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'friend request failed (${response.statusCode}): ${response.body}',
      );
    }
    return response;
  }
}
