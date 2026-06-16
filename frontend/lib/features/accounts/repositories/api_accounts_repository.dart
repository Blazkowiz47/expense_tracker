import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/core/utils/backend_date_codec.dart';
import 'package:expense_tracker/features/accounts/models/financial_account.dart';
import 'package:http/http.dart' as http;

class ApiAccountsRepository {
  ApiAccountsRepository({
    required http.Client client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client,
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;

  Future<List<FinancialAccount>> fetchAccounts({
    bool includeArchived = false,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/accounts').replace(
      queryParameters: includeArchived
          ? const <String, String>{'includeArchived': 'true'}
          : null,
    );
    final response = await _client.get(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception(
        'accounts request failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['accounts'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FinancialAccount.fromJson)
        .toList(growable: false);
  }

  Future<FinancialAccount> createAccount({
    required String name,
    String institution = '',
    String accountType = 'savings',
    required String currency,
    double openingBalance = 0,
    DateTime? balanceAsOf,
    String familyVisibility = 'private',
    String notes = '',
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/accounts');
    final response = await _client.post(
      uri,
      headers: await _headers(json: true),
      body: jsonEncode(<String, dynamic>{
        'name': name,
        'institution': institution,
        'accountType': accountType,
        'currency': currency,
        'openingBalance': openingBalance,
        if (balanceAsOf != null)
          'balanceAsOf': BackendDateCodec.encodeDate(balanceAsOf),
        'familyVisibility': familyVisibility,
        'notes': notes,
      }),
    );
    if (response.statusCode != 201) {
      throw Exception(
        'create account failed (${response.statusCode}): ${response.body}',
      );
    }
    return FinancialAccount.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<FinancialAccount> updateAccount({
    required String id,
    required String name,
    String institution = '',
    String accountType = 'savings',
    required String currency,
    double openingBalance = 0,
    DateTime? balanceAsOf,
    String familyVisibility = 'private',
    String notes = '',
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/accounts/$id');
    final response = await _client.put(
      uri,
      headers: await _headers(json: true),
      body: jsonEncode(<String, dynamic>{
        'name': name,
        'institution': institution,
        'accountType': accountType,
        'currency': currency,
        'openingBalance': openingBalance,
        if (balanceAsOf != null)
          'balanceAsOf': BackendDateCodec.encodeDate(balanceAsOf),
        'familyVisibility': familyVisibility,
        'notes': notes,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'update account failed (${response.statusCode}): ${response.body}',
      );
    }
    return FinancialAccount.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> archiveAccount(String id) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/accounts/$id');
    final response = await _client.delete(uri, headers: await _headers());
    if (response.statusCode != 204) {
      throw Exception(
        'archive account failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await _authTokenProvider.getBearerToken();
    return <String, String>{
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }
}
