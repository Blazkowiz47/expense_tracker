import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/data/models/freshness_snapshot.dart';
import 'package:http/http.dart' as http;

class FreshnessRepository {
  FreshnessRepository({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final bool _ownsClient;
  final AuthTokenProvider _authTokenProvider;

  Future<FreshnessSnapshot> fetchFreshness({
    DateTime? since,
    Iterable<String> sections = const [],
  }) async {
    final params = <String, String>{};
    if (since != null) {
      params['since'] = since.toUtc().toIso8601String();
    }
    final sectionList = sections
        .map((section) => section.trim())
        .where((section) => section.isNotEmpty)
        .toList(growable: false);
    if (sectionList.isNotEmpty) {
      params['sections'] = sectionList.join(',');
    }

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/sync/freshness',
    ).replace(queryParameters: params.isEmpty ? null : params);
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client
        .get(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        'freshness request failed (${response.statusCode}): ${response.body}',
      );
    }

    return FreshnessSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
