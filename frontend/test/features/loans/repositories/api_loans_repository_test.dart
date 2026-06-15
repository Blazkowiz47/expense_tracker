import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/features/loans/repositories/api_loans_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeAuthTokenProvider implements AuthTokenProvider {
  const _FakeAuthTokenProvider();

  @override
  Future<String> getBearerToken() async => 'session-token';
}

void main() {
  test('creates existing loan snapshot payload from current balance', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.headers['authorization'], 'Bearer session-token');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['currentPrincipalAmount'], 146087.67);
      expect(payload['principalAmount'], 146087.67);
      expect(payload['openingPrincipalAmount'], 146087.67);
      expect(payload['originalPrincipalAmount'], 150534);
      expect(payload['emiAmount'], 3733);
      expect(payload['currency'], 'NOK');
      expect(payload['interestRate'], 7.9);
      expect(payload['rateType'], 'floating');
      expect(payload['totalEmis'], 46);
      expect(payload['remainingEmis'], 46);
      expect(payload['dueDay'], 18);
      expect(payload['trackingStartedAt'], '2026-06-18T00:00:00.000Z');
      return http.Response(
        jsonEncode({
          'id': 'loan-1',
          'name': 'Car loan',
          'lender': 'Santander',
          'loanType': 'Car',
          'principalAmount': 146087.67,
          'openingPrincipalAmount': 146087.67,
          'originalPrincipalAmount': 150534,
          'emiAmount': 3733,
          'currency': 'NOK',
          'interestRate': 7.9,
          'rateType': 'floating',
          'totalEmis': 46,
          'paidEmiCount': 0,
          'remainingEmis': 46,
          'totalPaidAmount': 0,
          'prepaymentAmount': 0,
          'estimatedOutstanding': 146087.67,
          'dueDay': 18,
          'startDate': '2026-06-18T00:00:00Z',
          'trackingStartedAt': '2026-06-18T00:00:00Z',
          'nextDueDate': '2026-06-18T00:00:00Z',
          'category': 'Loans / EMI',
          'notes': '',
          'archived': false,
        }),
        201,
      );
    });
    final repository = ApiLoansRepository(
      client: client,
      authTokenProvider: const _FakeAuthTokenProvider(),
    );

    final loan = await repository.createLoan(
      name: 'Car loan',
      lender: 'Santander',
      loanType: 'Car',
      principalAmount: 146087.67,
      originalPrincipalAmount: 150534,
      emiAmount: 3733,
      currency: 'NOK',
      interestRate: 7.9,
      rateType: 'floating',
      totalEmis: 46,
      dueDay: 18,
      startDate: DateTime.utc(2026, 6, 18),
      category: 'Loans / EMI',
      notes: '',
    );

    expect(requests, hasLength(1));
    expect(loan.rateType, 'floating');
    expect(loan.openingPrincipalAmount, 146087.67);
    expect(loan.originalPrincipalAmount, 150534);
    expect(loan.remainingEmis, 46);
  });
}
