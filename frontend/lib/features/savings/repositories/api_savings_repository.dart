import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/core/utils/backend_date_codec.dart';
import 'package:expense_tracker/features/savings/models/savings_goal.dart';
import 'package:http/http.dart' as http;

class ApiSavingsRepository {
  ApiSavingsRepository({
    required http.Client client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client,
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;

  Future<List<SavingsGoal>> fetchGoals({bool includeArchived = false}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/savings/goals').replace(
      queryParameters: includeArchived
          ? const <String, String>{'includeArchived': 'true'}
          : null,
    );
    final response = await _client.get(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception(
        'savings goals request failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['goals'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SavingsGoal.fromJson)
        .toList(growable: false);
  }

  Future<SavingsGoal> createGoal({
    required String name,
    String goalType = 'savings_goal',
    String familyVisibility = 'private',
    required double targetAmount,
    required String targetCurrency,
    required String sourceCurrency,
    required double monthlyTargetAmount,
    required String startMonth,
    String provider = '',
    String accountName = '',
    double expectedReturnRate = 0,
    DateTime? maturityDate,
    required String notes,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/savings/goals');
    final response = await _client.post(
      uri,
      headers: await _headers(json: true),
      body: jsonEncode(
        _goalBody(
          name: name,
          goalType: goalType,
          familyVisibility: familyVisibility,
          targetAmount: targetAmount,
          targetCurrency: targetCurrency,
          sourceCurrency: sourceCurrency,
          monthlyTargetAmount: monthlyTargetAmount,
          startMonth: startMonth,
          provider: provider,
          accountName: accountName,
          expectedReturnRate: expectedReturnRate,
          maturityDate: maturityDate,
          notes: notes,
        ),
      ),
    );
    if (response.statusCode != 201) {
      throw Exception(
        'create savings goal failed (${response.statusCode}): ${response.body}',
      );
    }
    return SavingsGoal.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SavingsGoal> updateGoal({
    required String id,
    required String name,
    String goalType = 'savings_goal',
    String familyVisibility = 'private',
    required double targetAmount,
    required String targetCurrency,
    required String sourceCurrency,
    required double monthlyTargetAmount,
    required String startMonth,
    String provider = '',
    String accountName = '',
    double expectedReturnRate = 0,
    DateTime? maturityDate,
    required String notes,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/savings/goals/$id');
    final response = await _client.put(
      uri,
      headers: await _headers(json: true),
      body: jsonEncode(
        _goalBody(
          name: name,
          goalType: goalType,
          familyVisibility: familyVisibility,
          targetAmount: targetAmount,
          targetCurrency: targetCurrency,
          sourceCurrency: sourceCurrency,
          monthlyTargetAmount: monthlyTargetAmount,
          startMonth: startMonth,
          provider: provider,
          accountName: accountName,
          expectedReturnRate: expectedReturnRate,
          maturityDate: maturityDate,
          notes: notes,
        ),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'update savings goal failed (${response.statusCode}): ${response.body}',
      );
    }
    return SavingsGoal.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> archiveGoal(String id) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/savings/goals/$id');
    final response = await _client.delete(uri, headers: await _headers());
    if (response.statusCode != 204) {
      throw Exception(
        'archive savings goal failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<List<SavingsContribution>> fetchContributions(String goalId) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/savings/goals/$goalId/contributions',
    );
    final response = await _client.get(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception(
        'savings contributions request failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['contributions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SavingsContribution.fromJson)
        .toList(growable: false);
  }

  Future<SavingsContributionResult> addContribution({
    required String goalId,
    required double sourceAmount,
    required String sourceCurrency,
    required DateTime date,
    double? targetAmount,
    double feeAmount = 0,
    String? feeCurrency,
    String notes = '',
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/savings/goals/$goalId/contributions',
    );
    final response = await _client.post(
      uri,
      headers: await _headers(json: true),
      body: jsonEncode(<String, dynamic>{
        'sourceAmount': sourceAmount,
        'sourceCurrency': sourceCurrency,
        if (targetAmount != null) 'targetAmount': targetAmount,
        'feeAmount': feeAmount,
        if (feeCurrency != null) 'feeCurrency': feeCurrency,
        'date': BackendDateCodec.encodeDate(date),
        'notes': notes,
      }),
    );
    if (response.statusCode != 201) {
      throw Exception(
        'add savings contribution failed (${response.statusCode}): ${response.body}',
      );
    }
    return SavingsContributionResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SavingsContributionResult> updateContribution({
    required String goalId,
    required String contributionId,
    required DateTime date,
    String? notes,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/savings/goals/$goalId/contributions/$contributionId',
    );
    final response = await _client.put(
      uri,
      headers: await _headers(json: true),
      body: jsonEncode(<String, dynamic>{
        'date': BackendDateCodec.encodeDate(date),
        if (notes != null) 'notes': notes,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'update savings contribution failed (${response.statusCode}): ${response.body}',
      );
    }
    return SavingsContributionResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await _authTokenProvider.getBearerToken();
    return <String, String>{
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _goalBody({
    required String name,
    required String goalType,
    required String familyVisibility,
    required double targetAmount,
    required String targetCurrency,
    required String sourceCurrency,
    required double monthlyTargetAmount,
    required String startMonth,
    required String provider,
    required String accountName,
    required double expectedReturnRate,
    required DateTime? maturityDate,
    required String notes,
  }) {
    return <String, dynamic>{
      'name': name,
      'goalType': goalType,
      'familyVisibility': familyVisibility,
      'targetAmount': targetAmount,
      'targetCurrency': targetCurrency,
      'sourceCurrency': sourceCurrency,
      'monthlyTargetAmount': monthlyTargetAmount,
      'startMonth': startMonth,
      'provider': provider,
      'accountName': accountName,
      'expectedReturnRate': expectedReturnRate,
      if (maturityDate != null)
        'maturityDate': BackendDateCodec.encodeDate(maturityDate),
      'notes': notes,
    };
  }
}
