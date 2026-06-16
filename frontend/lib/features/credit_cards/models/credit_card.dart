class CreditCardAccount {
  const CreditCardAccount({
    required this.id,
    required this.name,
    required this.issuer,
    required this.network,
    required this.last4,
    required this.currency,
    required this.creditLimit,
    required this.currentBalance,
    required this.availableCredit,
    required this.balanceAsOf,
    required this.statementDay,
    required this.dueDay,
    required this.cycleStart,
    required this.statementDate,
    required this.paymentDueDate,
    required this.currentCycleSpend,
    required this.familyVisibility,
    required this.notes,
    required this.archived,
  });

  final String id;
  final String name;
  final String issuer;
  final String network;
  final String last4;
  final String currency;
  final double creditLimit;
  final double currentBalance;
  final double availableCredit;
  final DateTime? balanceAsOf;
  final int statementDay;
  final int dueDay;
  final DateTime? cycleStart;
  final DateTime? statementDate;
  final DateTime? paymentDueDate;
  final double currentCycleSpend;
  final String familyVisibility;
  final String notes;
  final bool archived;

  factory CreditCardAccount.fromJson(Map<String, dynamic> json) {
    return CreditCardAccount(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      issuer: (json['issuer'] as String?) ?? '',
      network: (json['network'] as String?) ?? '',
      last4: (json['last4'] as String?) ?? '',
      currency: ((json['currency'] as String?) ?? 'NOK').toUpperCase(),
      creditLimit: _asDouble(json['creditLimit']),
      currentBalance: _asDouble(json['currentBalance']),
      availableCredit: _asDouble(json['availableCredit']),
      balanceAsOf: _parseDate(json['balanceAsOf']),
      statementDay: _asInt(json['statementDay'], fallback: 1),
      dueDay: _asInt(json['dueDay'], fallback: 1),
      cycleStart: _parseDate(json['cycleStart']),
      statementDate: _parseDate(json['statementDate'] ?? json['cycleEnd']),
      paymentDueDate: _parseDate(json['paymentDueDate']),
      currentCycleSpend: _asDouble(json['currentCycleSpend']),
      familyVisibility: (json['familyVisibility'] as String?) ?? 'private',
      notes: (json['notes'] as String?) ?? '',
      archived: json['archived'] as bool? ?? false,
    );
  }
}

class CreditCardSpendResult {
  const CreditCardSpendResult({required this.card, required this.expense});

  final CreditCardAccount card;
  final Map<String, dynamic> expense;

  factory CreditCardSpendResult.fromJson(Map<String, dynamic> json) {
    final expense = json['expense'];
    return CreditCardSpendResult(
      card: CreditCardAccount.fromJson(
        json['card'] is Map<String, dynamic>
            ? json['card'] as Map<String, dynamic>
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
  return double.tryParse(value?.toString().replaceAll(',', '') ?? '') ?? 0;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime? _parseDate(Object? value) {
  final raw = value?.toString() ?? '';
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
