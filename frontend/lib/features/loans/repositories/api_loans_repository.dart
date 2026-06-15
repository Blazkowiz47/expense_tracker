import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/features/loans/models/loan.dart';
import 'package:http/http.dart' as http;

class ApiLoansRepository {
  ApiLoansRepository({
    required http.Client client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client,
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;

  Future<List<Loan>> fetchLoans({bool includeArchived = false}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/loans').replace(
      queryParameters: includeArchived
          ? const <String, String>{'includeArchived': 'true'}
          : null,
    );
    final response = await _client.get(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception(
        'loans request failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['loans'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Loan.fromJson)
        .toList(growable: false);
  }

  Future<Loan> createLoan({
    required String name,
    required String lender,
    required String loanType,
    required double principalAmount,
    double originalPrincipalAmount = 0,
    required double emiAmount,
    required String currency,
    required double interestRate,
    String rateType = 'fixed',
    required int totalEmis,
    required int dueDay,
    required DateTime startDate,
    required String category,
    required String notes,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/loans');
    final response = await _client.post(
      uri,
      headers: await _headers(json: true),
      body: jsonEncode(
        _loanBody(
          name: name,
          lender: lender,
          loanType: loanType,
          principalAmount: principalAmount,
          originalPrincipalAmount: originalPrincipalAmount,
          emiAmount: emiAmount,
          currency: currency,
          interestRate: interestRate,
          rateType: rateType,
          totalEmis: totalEmis,
          dueDay: dueDay,
          startDate: startDate,
          category: category,
          notes: notes,
        ),
      ),
    );
    if (response.statusCode != 201) {
      throw Exception(
        'create loan failed (${response.statusCode}): ${response.body}',
      );
    }
    return Loan.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Loan> updateLoan({
    required String id,
    required String name,
    required String lender,
    required String loanType,
    required double principalAmount,
    double originalPrincipalAmount = 0,
    required double emiAmount,
    required String currency,
    required double interestRate,
    String rateType = 'fixed',
    required int totalEmis,
    required int dueDay,
    required DateTime startDate,
    required String category,
    required String notes,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/loans/$id');
    final response = await _client.put(
      uri,
      headers: await _headers(json: true),
      body: jsonEncode(
        _loanBody(
          name: name,
          lender: lender,
          loanType: loanType,
          principalAmount: principalAmount,
          originalPrincipalAmount: originalPrincipalAmount,
          emiAmount: emiAmount,
          currency: currency,
          interestRate: interestRate,
          rateType: rateType,
          totalEmis: totalEmis,
          dueDay: dueDay,
          startDate: startDate,
          category: category,
          notes: notes,
        ),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'update loan failed (${response.statusCode}): ${response.body}',
      );
    }
    return Loan.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> archiveLoan(String id) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/loans/$id');
    final response = await _client.delete(uri, headers: await _headers());
    if (response.statusCode != 204) {
      throw Exception(
        'archive loan failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<List<LoanPayment>> fetchPayments(String loanId) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/loans/$loanId/payments');
    final response = await _client.get(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception(
        'loan payments request failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['payments'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LoanPayment.fromJson)
        .toList(growable: false);
  }

  Future<LoanPaymentResult> logPayment({
    required String loanId,
    required String paymentType,
    required double amount,
    required DateTime date,
    String notes = '',
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/loans/$loanId/payments');
    final response = await _client.post(
      uri,
      headers: await _headers(json: true),
      body: jsonEncode(<String, dynamic>{
        'paymentType': paymentType,
        'amount': amount,
        'date': date.toUtc().toIso8601String(),
        'notes': notes,
      }),
    );
    if (response.statusCode != 201) {
      throw Exception(
        'log loan payment failed (${response.statusCode}): ${response.body}',
      );
    }
    return LoanPaymentResult.fromJson(
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

  Map<String, dynamic> _loanBody({
    required String name,
    required String lender,
    required String loanType,
    required double principalAmount,
    required double originalPrincipalAmount,
    required double emiAmount,
    required String currency,
    required double interestRate,
    required String rateType,
    required int totalEmis,
    required int dueDay,
    required DateTime startDate,
    required String category,
    required String notes,
  }) {
    return <String, dynamic>{
      'name': name,
      'lender': lender,
      'loanType': loanType,
      'currentPrincipalAmount': principalAmount,
      'principalAmount': principalAmount,
      'openingPrincipalAmount': principalAmount,
      if (originalPrincipalAmount > 0)
        'originalPrincipalAmount': originalPrincipalAmount,
      'emiAmount': emiAmount,
      'currency': currency,
      'interestRate': interestRate,
      'rateType': rateType,
      'totalEmis': totalEmis,
      'remainingEmis': totalEmis,
      'dueDay': dueDay,
      'startDate': startDate.toUtc().toIso8601String(),
      'trackingStartedAt': startDate.toUtc().toIso8601String(),
      'category': category,
      'notes': notes,
    };
  }
}
