import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/features/recurring/models/recurring_template.dart';
import 'package:http/http.dart' as http;

class ApiRecurringRepository {
  ApiRecurringRepository({
    required http.Client client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client,
       _authTokenProvider =
           authTokenProvider ?? const FirebaseAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;

  Future<List<RecurringTemplate>> fetchTemplates() async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/recurring/templates');
    final response = await _client.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'recurring templates request failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final templates = (payload['templates'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RecurringTemplate.fromJson)
        .toList(growable: false);
    return templates;
  }

  Future<RecurringTemplate> createTemplate({
    required String title,
    required double amount,
    required String category,
    required String frequency,
    required DateTime startDate,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/recurring/templates');
    final response = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(<String, dynamic>{
        'title': title,
        'amount': amount,
        'category': category,
        'frequency': frequency,
        'startDate': startDate.toUtc().toIso8601String(),
      }),
    );
    if (response.statusCode != 201) {
      throw Exception(
        'create recurring template failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return RecurringTemplate.fromJson(payload);
  }

  Future<int> processDueTemplates() async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/recurring/process-due');
    final response = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'process due recurring templates failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['created'] as num?)?.toInt() ?? 0;
  }
}
