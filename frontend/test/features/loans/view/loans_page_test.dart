import 'package:expense_tracker/features/loans/models/loan.dart';
import 'package:expense_tracker/features/loans/repositories/api_loans_repository.dart';
import 'package:expense_tracker/features/loans/view/loans_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeLoansRepository extends ApiLoansRepository {
  _FakeLoansRepository({List<Loan> loans = const []})
    : _loans = List<Loan>.of(loans),
      super(client: MockClient((_) async => http.Response('{}', 200)));

  var _loans = <Loan>[];
  _CreatedLoan? createdLoan;
  String? loggedLoanId;
  String? loggedPaymentType;
  double? loggedAmount;

  @override
  Future<List<Loan>> fetchLoans({bool includeArchived = false}) async {
    return _loans.where((loan) => includeArchived || !loan.archived).toList();
  }

  @override
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
    createdLoan = _CreatedLoan(
      name: name,
      principalAmount: principalAmount,
      originalPrincipalAmount: originalPrincipalAmount,
      emiAmount: emiAmount,
      interestRate: interestRate,
      rateType: rateType,
      totalEmis: totalEmis,
      dueDay: dueDay,
    );
    final loan = _loan(
      id: 'created-loan',
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
    );
    _loans = [loan, ..._loans];
    return loan;
  }

  @override
  Future<LoanPaymentResult> logPayment({
    required String loanId,
    required String paymentType,
    required double amount,
    required DateTime date,
    String notes = '',
  }) async {
    loggedLoanId = loanId;
    loggedPaymentType = paymentType;
    loggedAmount = amount;
    final existing = _loans.firstWhere((loan) => loan.id == loanId);
    final paidEmis = existing.paidEmiCount + (paymentType == 'emi' ? 1 : 0);
    final updated = existing.copyWith(
      paidEmiCount: paidEmis,
      remainingEmis: existing.totalEmis > 0
          ? (existing.totalEmis - paidEmis).clamp(0, existing.totalEmis).toInt()
          : null,
      totalPaidAmount: existing.totalPaidAmount + amount,
      estimatedOutstanding: (existing.estimatedOutstanding - amount)
          .clamp(0, existing.principalAmount)
          .toDouble(),
      lastPaymentAt: date,
    );
    _loans = _loans
        .map((loan) => loan.id == loanId ? updated : loan)
        .toList(growable: false);
    return LoanPaymentResult(
      loan: updated,
      payment: LoanPayment(
        id: 'payment-1',
        loanId: loanId,
        paymentType: paymentType,
        period: '${date.year}-${date.month.toString().padLeft(2, '0')}',
        amount: amount,
        currency: existing.currency,
        date: date,
        expenseId: 'expense-1',
        notes: notes,
        createdAt: date,
        updatedAt: date,
      ),
      expense: const <String, dynamic>{'id': 'expense-1'},
    );
  }
}

class _CreatedLoan {
  const _CreatedLoan({
    required this.name,
    required this.principalAmount,
    required this.originalPrincipalAmount,
    required this.emiAmount,
    required this.interestRate,
    required this.rateType,
    required this.totalEmis,
    required this.dueDay,
  });

  final String name;
  final double principalAmount;
  final double originalPrincipalAmount;
  final double emiAmount;
  final double interestRate;
  final String rateType;
  final int totalEmis;
  final int dueDay;
}

Loan _loan({
  String id = 'loan-1',
  String name = 'Car loan',
  String lender = 'Bank',
  String loanType = 'Car',
  double principalAmount = 120000,
  double originalPrincipalAmount = 0,
  double emiAmount = 5000,
  String currency = 'INR',
  double interestRate = 0,
  String rateType = 'fixed',
  int totalEmis = 12,
  int dueDay = 5,
  int paidEmiCount = 0,
  DateTime? startDate,
  String category = 'Loans / EMI',
  String notes = '',
}) {
  return Loan(
    id: id,
    name: name,
    lender: lender,
    loanType: loanType,
    principalAmount: principalAmount,
    openingPrincipalAmount: principalAmount,
    originalPrincipalAmount: originalPrincipalAmount,
    emiAmount: emiAmount,
    currency: currency,
    interestRate: interestRate,
    rateType: rateType,
    totalEmis: totalEmis,
    paidEmiCount: paidEmiCount,
    remainingEmis: totalEmis - paidEmiCount,
    totalPaidAmount: paidEmiCount * emiAmount,
    prepaymentAmount: 0,
    estimatedOutstanding: principalAmount - (paidEmiCount * emiAmount),
    dueDay: dueDay,
    startDate: startDate ?? DateTime.utc(2026, 6, 5),
    trackingStartedAt: startDate ?? DateTime.utc(2026, 6, 5),
    nextDueDate: DateTime.utc(2026, 6, dueDay),
    lastPaymentAt: null,
    category: category,
    notes: notes,
    archived: false,
    archivedAt: null,
    createdAt: DateTime.utc(2026, 6, 1),
    updatedAt: DateTime.utc(2026, 6, 1),
  );
}

void main() {
  testWidgets('adds an existing floating car loan from current balance', (
    tester,
  ) async {
    final repository = _FakeLoansRepository();
    await tester.pumpWidget(
      MaterialApp(home: LoansPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No loans logged'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add loan'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Car loan');
    await tester.enterText(fields.at(1), 'Santander');
    await tester.enterText(fields.at(2), '146087.67');
    await tester.enterText(fields.at(3), '3733');
    await tester.enterText(fields.at(4), '150534');
    await tester.enterText(fields.at(5), '3');
    await tester.enterText(fields.at(6), '10');
    await tester.enterText(fields.at(7), '7.90');

    await tester.ensureVisible(find.text('Fixed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Floating').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.createdLoan?.name, 'Car loan');
    expect(repository.createdLoan?.principalAmount, 146087.67);
    expect(repository.createdLoan?.originalPrincipalAmount, 150534);
    expect(repository.createdLoan?.emiAmount, 3733);
    expect(repository.createdLoan?.interestRate, 7.9);
    expect(repository.createdLoan?.rateType, 'floating');
    expect(repository.createdLoan?.totalEmis, 46);
    expect(repository.createdLoan?.dueDay, DateTime.now().day);
    expect(find.text('Car loan'), findsOneWidget);
  });

  testWidgets('logs an EMI for an existing loan', (tester) async {
    final repository = _FakeLoansRepository(loans: [_loan()]);
    await tester.pumpWidget(
      MaterialApp(home: LoansPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log EMI'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.loggedLoanId, 'loan-1');
    expect(repository.loggedPaymentType, 'emi');
    expect(repository.loggedAmount, 5000);
    expect(find.textContaining('Progress: 1/12'), findsOneWidget);
    expect(find.text('EMI logged as expense.'), findsOneWidget);
  });
}
