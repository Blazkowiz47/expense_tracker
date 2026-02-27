import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:http/http.dart' as http;

class ApiGroupsRepository {
  ApiGroupsRepository({
    required http.Client client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client,
       _authTokenProvider =
           authTokenProvider ?? const FirebaseAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;

  Future<List<GroupSummary>> fetchGroups() async {
    final response = await _request(method: 'GET', path: '/api/v1/groups');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawGroups = (payload['groups'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    return rawGroups.map(GroupSummary.fromJson).toList(growable: false);
  }

  Future<GroupSummary> createGroup({
    required String name,
    required GroupType groupType,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/api/v1/groups',
      body: <String, dynamic>{'name': name, 'groupType': groupType.name},
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return GroupSummary.fromJson(payload);
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
      _ => throw UnsupportedError('Unsupported method $method'),
    };

    final response = await request.timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'group request failed (${response.statusCode}): ${response.body}',
      );
    }
    return response;
  }
}
