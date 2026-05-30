import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:http/http.dart' as http;

class MonthlyPlanRepository {
  MonthlyPlanRepository({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client ?? http.Client(),
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;

  Future<MonthlyPlan> fetchPlan({required String month}) async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/planning/monthly',
    ).replace(queryParameters: {'month': month});
    final response = await _client.get(
      uri,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception(
        'monthly plan request failed (${response.statusCode}): ${response.body}',
      );
    }
    return MonthlyPlan.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<MonthlyPlan> savePlan({
    required String month,
    required String currency,
    required Map<String, double> budgets,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/planning/monthly');
    final response = await _client.put(
      uri,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'month': month,
        'currency': currency,
        'budgets': budgets,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'monthly plan save failed (${response.statusCode}): ${response.body}',
      );
    }
    return MonthlyPlan.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  void dispose() => _client.close();
}
