import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/core/utils/backend_date_codec.dart';
import 'package:expense_tracker/features/recurring/models/recurring_template.dart';
import 'package:http/http.dart' as http;

class ApiRecurringRepository {
  ApiRecurringRepository({
    required http.Client client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client,
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider();

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
    required String kind,
    required double amount,
    required String category,
    required String currency,
    required String frequency,
    required int dayOfMonth,
    required DateTime startDate,
    String? sourceAccountName,
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
        'kind': kind,
        'amount': amount,
        'currency': currency,
        'category': category,
        'frequency': frequency,
        'dayOfMonth': dayOfMonth,
        'startDate': BackendDateCodec.encodeDate(startDate),
        if (sourceAccountName?.trim().isNotEmpty == true)
          'sourceAccountName': sourceAccountName!.trim(),
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

  Future<RecurringTemplate> updateTemplate({
    required String id,
    required String title,
    required String kind,
    required double amount,
    required String category,
    required String currency,
    required String frequency,
    required int dayOfMonth,
    DateTime? startDate,
    String? sourceAccountName,
  }) {
    return _updateTemplate(
      id: id,
      body: <String, dynamic>{
        'title': title,
        'kind': kind,
        'amount': amount,
        'currency': currency,
        'category': category,
        'frequency': frequency,
        'dayOfMonth': dayOfMonth,
        'sourceAccountName': sourceAccountName?.trim() ?? '',
        if (startDate != null)
          'startDate': BackendDateCodec.encodeDate(startDate),
      },
    );
  }

  Future<RecurringTemplate> pauseTemplate(String id) {
    return _updateTemplate(
      id: id,
      body: const <String, dynamic>{'active': false},
    );
  }

  Future<RecurringTemplate> resumeTemplate(String id) {
    return _updateTemplate(
      id: id,
      body: const <String, dynamic>{'active': true},
    );
  }

  Future<RecurringTemplate> _updateTemplate({
    required String id,
    required Map<String, dynamic> body,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/recurring/templates/$id',
    );
    final response = await _client.put(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'update recurring template failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return RecurringTemplate.fromJson(payload);
  }

  Future<void> deleteTemplate(String id) async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/recurring/templates/$id',
    );
    final response = await _client.delete(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 204) {
      throw Exception(
        'delete recurring template failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<List<RecurringOccurrence>> fetchOccurrences({
    required String month,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/recurring/occurrences',
    ).replace(queryParameters: <String, String>{'month': month});
    final response = await _client.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'recurring occurrences request failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final occurrences = (payload['occurrences'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RecurringOccurrence.fromJson)
        .toList(growable: false);
    return occurrences;
  }

  Future<RecurringOccurrence> confirmOccurrence({
    required String occurrenceId,
    required double actualAmount,
    required DateTime actualDate,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/recurring/occurrences/$occurrenceId/confirm',
    );
    final response = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(<String, dynamic>{
        'actualAmount': actualAmount,
        'actualDate': BackendDateCodec.encodeDate(actualDate),
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'confirm recurring occurrence failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return RecurringOccurrence.fromJson(payload);
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
