import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/features/activity/models/activity_feed.dart';
import 'package:http/http.dart' as http;

class ActivityFeedRepository {
  ActivityFeedRepository({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final bool _ownsClient;
  final AuthTokenProvider _authTokenProvider;

  Future<ActivityFeed> fetchActivity({
    DateTime? since,
    int limit = 80,
    Iterable<String> include = const ['personal', 'group'],
  }) async {
    final params = <String, String>{'limit': limit.clamp(1, 200).toString()};
    if (since != null) {
      params['since'] = since.toUtc().toIso8601String();
    }
    final includeList = include
        .map((section) => section.trim())
        .where((section) => section.isNotEmpty)
        .toList(growable: false);
    if (includeList.isNotEmpty) {
      params['include'] = includeList.join(',');
    }

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/activity',
    ).replace(queryParameters: params);
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
        'activity request failed (${response.statusCode}): ${response.body}',
      );
    }

    return ActivityFeed.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
