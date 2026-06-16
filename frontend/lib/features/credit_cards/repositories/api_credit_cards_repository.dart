import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/core/utils/backend_date_codec.dart';
import 'package:expense_tracker/features/credit_cards/models/credit_card.dart';
import 'package:http/http.dart' as http;

class ApiCreditCardsRepository {
  ApiCreditCardsRepository({
    required http.Client client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client,
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;

  Future<List<CreditCardAccount>> fetchCards({
    bool includeArchived = false,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/credit-cards').replace(
      queryParameters: includeArchived
          ? const <String, String>{'includeArchived': 'true'}
          : null,
    );
    final response = await _client.get(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception(
        'credit cards request failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['cards'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CreditCardAccount.fromJson)
        .toList(growable: false);
  }

  Future<CreditCardAccount> createCard({
    required String name,
    String issuer = '',
    String network = '',
    String last4 = '',
    required String currency,
    double creditLimit = 0,
    double currentBalance = 0,
    required int statementDay,
    required int dueDay,
    String familyVisibility = 'private',
    String notes = '',
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/credit-cards');
    final response = await _client.post(
      uri,
      headers: await _headers(json: true),
      body: jsonEncode(
        _cardBody(
          name: name,
          issuer: issuer,
          network: network,
          last4: last4,
          currency: currency,
          creditLimit: creditLimit,
          currentBalance: currentBalance,
          statementDay: statementDay,
          dueDay: dueDay,
          familyVisibility: familyVisibility,
          notes: notes,
        ),
      ),
    );
    if (response.statusCode != 201) {
      throw Exception(
        'create credit card failed (${response.statusCode}): ${response.body}',
      );
    }
    return CreditCardAccount.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CreditCardAccount> updateCard({
    required String id,
    required String name,
    String issuer = '',
    String network = '',
    String last4 = '',
    required String currency,
    double creditLimit = 0,
    double currentBalance = 0,
    required int statementDay,
    required int dueDay,
    String familyVisibility = 'private',
    String notes = '',
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/credit-cards/$id');
    final response = await _client.put(
      uri,
      headers: await _headers(json: true),
      body: jsonEncode(
        _cardBody(
          name: name,
          issuer: issuer,
          network: network,
          last4: last4,
          currency: currency,
          creditLimit: creditLimit,
          currentBalance: currentBalance,
          statementDay: statementDay,
          dueDay: dueDay,
          familyVisibility: familyVisibility,
          notes: notes,
        ),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'update credit card failed (${response.statusCode}): ${response.body}',
      );
    }
    return CreditCardAccount.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> archiveCard(String id) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/credit-cards/$id');
    final response = await _client.delete(uri, headers: await _headers());
    if (response.statusCode != 204) {
      throw Exception(
        'archive credit card failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<CreditCardSpendResult> logSpend({
    required String cardId,
    required double amount,
    required String category,
    required String description,
    required DateTime date,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/credit-cards/$cardId/spend',
    );
    final response = await _client.post(
      uri,
      headers: await _headers(json: true),
      body: jsonEncode(<String, dynamic>{
        'amount': amount,
        'category': category,
        'description': description,
        'date': BackendDateCodec.encodeDate(date),
      }),
    );
    if (response.statusCode != 201) {
      throw Exception(
        'log credit card spend failed (${response.statusCode}): ${response.body}',
      );
    }
    return CreditCardSpendResult.fromJson(
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

  Map<String, dynamic> _cardBody({
    required String name,
    required String issuer,
    required String network,
    required String last4,
    required String currency,
    required double creditLimit,
    required double currentBalance,
    required int statementDay,
    required int dueDay,
    required String familyVisibility,
    required String notes,
  }) {
    return <String, dynamic>{
      'name': name,
      'issuer': issuer,
      'network': network,
      'last4': last4,
      'currency': currency,
      'creditLimit': creditLimit,
      'currentBalance': currentBalance,
      'statementDay': statementDay,
      'dueDay': dueDay,
      'familyVisibility': familyVisibility,
      'notes': notes,
    };
  }
}
