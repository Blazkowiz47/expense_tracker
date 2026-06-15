class Loan {
  const Loan({
    required this.id,
    required this.name,
    required this.lender,
    required this.loanType,
    required this.principalAmount,
    required this.emiAmount,
    required this.currency,
    required this.interestRate,
    required this.totalEmis,
    required this.paidEmiCount,
    required this.remainingEmis,
    required this.totalPaidAmount,
    required this.prepaymentAmount,
    required this.estimatedOutstanding,
    required this.dueDay,
    required this.startDate,
    required this.nextDueDate,
    required this.lastPaymentAt,
    required this.category,
    required this.notes,
    required this.archived,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String lender;
  final String loanType;
  final double principalAmount;
  final double emiAmount;
  final String currency;
  final double interestRate;
  final int totalEmis;
  final int paidEmiCount;
  final int? remainingEmis;
  final double totalPaidAmount;
  final double prepaymentAmount;
  final double estimatedOutstanding;
  final int dueDay;
  final DateTime startDate;
  final DateTime? nextDueDate;
  final DateTime? lastPaymentAt;
  final String category;
  final String notes;
  final bool archived;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Loan.fromJson(Map<String, dynamic> json) {
    return Loan(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      lender: (json['lender'] as String?) ?? '',
      loanType: (json['loanType'] as String?) ?? 'Personal',
      principalAmount: _asDouble(json['principalAmount']),
      emiAmount: _asDouble(json['emiAmount']),
      currency: ((json['currency'] as String?) ?? 'INR').toUpperCase(),
      interestRate: _asDouble(json['interestRate']),
      totalEmis: _asInt(json['totalEmis']),
      paidEmiCount: _asInt(json['paidEmiCount']),
      remainingEmis: _nullableInt(json['remainingEmis']),
      totalPaidAmount: _asDouble(json['totalPaidAmount']),
      prepaymentAmount: _asDouble(json['prepaymentAmount']),
      estimatedOutstanding: _asDouble(json['estimatedOutstanding']),
      dueDay: _asInt(json['dueDay'], fallback: 1),
      startDate: _parseDate(json['startDate']) ?? DateTime.now(),
      nextDueDate: _parseDate(json['nextDueDate']),
      lastPaymentAt: _parseDate(json['lastPaymentAt']),
      category: (json['category'] as String?) ?? 'Loans / EMI',
      notes: (json['notes'] as String?) ?? '',
      archived: json['archived'] as bool? ?? false,
      archivedAt: _parseDate(json['archivedAt']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  Loan copyWith({
    String? id,
    String? name,
    String? lender,
    String? loanType,
    double? principalAmount,
    double? emiAmount,
    String? currency,
    double? interestRate,
    int? totalEmis,
    int? paidEmiCount,
    int? remainingEmis,
    double? totalPaidAmount,
    double? prepaymentAmount,
    double? estimatedOutstanding,
    int? dueDay,
    DateTime? startDate,
    DateTime? nextDueDate,
    DateTime? lastPaymentAt,
    String? category,
    String? notes,
    bool? archived,
    DateTime? archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Loan(
      id: id ?? this.id,
      name: name ?? this.name,
      lender: lender ?? this.lender,
      loanType: loanType ?? this.loanType,
      principalAmount: principalAmount ?? this.principalAmount,
      emiAmount: emiAmount ?? this.emiAmount,
      currency: currency ?? this.currency,
      interestRate: interestRate ?? this.interestRate,
      totalEmis: totalEmis ?? this.totalEmis,
      paidEmiCount: paidEmiCount ?? this.paidEmiCount,
      remainingEmis: remainingEmis ?? this.remainingEmis,
      totalPaidAmount: totalPaidAmount ?? this.totalPaidAmount,
      prepaymentAmount: prepaymentAmount ?? this.prepaymentAmount,
      estimatedOutstanding: estimatedOutstanding ?? this.estimatedOutstanding,
      dueDay: dueDay ?? this.dueDay,
      startDate: startDate ?? this.startDate,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      lastPaymentAt: lastPaymentAt ?? this.lastPaymentAt,
      category: category ?? this.category,
      notes: notes ?? this.notes,
      archived: archived ?? this.archived,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class LoanPayment {
  const LoanPayment({
    required this.id,
    required this.loanId,
    required this.paymentType,
    required this.period,
    required this.amount,
    required this.currency,
    required this.date,
    required this.expenseId,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String loanId;
  final String paymentType;
  final String period;
  final double amount;
  final String currency;
  final DateTime date;
  final String expenseId;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isEmi => paymentType == 'emi';

  factory LoanPayment.fromJson(Map<String, dynamic> json) {
    return LoanPayment(
      id: (json['id'] as String?) ?? '',
      loanId: (json['loanId'] as String?) ?? '',
      paymentType: (json['paymentType'] as String?) ?? 'emi',
      period: (json['period'] as String?) ?? '',
      amount: _asDouble(json['amount']),
      currency: ((json['currency'] as String?) ?? 'INR').toUpperCase(),
      date: _parseDate(json['date']) ?? DateTime.now(),
      expenseId: (json['expenseId'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }
}

class LoanPaymentResult {
  const LoanPaymentResult({
    required this.loan,
    required this.payment,
    required this.expense,
  });

  final Loan loan;
  final LoanPayment payment;
  final Map<String, dynamic> expense;

  factory LoanPaymentResult.fromJson(Map<String, dynamic> json) {
    final expense = json['expense'];
    return LoanPaymentResult(
      loan: Loan.fromJson(
        json['loan'] is Map<String, dynamic>
            ? json['loan'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
      payment: LoanPayment.fromJson(
        json['payment'] is Map<String, dynamic>
            ? json['payment'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
      expense: expense is Map<String, dynamic>
          ? Map<String, dynamic>.from(expense)
          : const <String, dynamic>{},
    );
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime? _parseDate(Object? value) {
  final raw = value?.toString() ?? '';
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
