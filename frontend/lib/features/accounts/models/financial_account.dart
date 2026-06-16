class FinancialAccount {
  const FinancialAccount({
    required this.id,
    required this.name,
    required this.institution,
    required this.accountType,
    required this.currency,
    required this.openingBalance,
    required this.balanceAsOf,
    required this.familyVisibility,
    required this.notes,
    required this.archived,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String institution;
  final String accountType;
  final String currency;
  final double openingBalance;
  final DateTime? balanceAsOf;
  final String familyVisibility;
  final String notes;
  final bool archived;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory FinancialAccount.fromJson(Map<String, dynamic> json) {
    return FinancialAccount(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      institution: (json['institution'] as String?) ?? '',
      accountType: (json['accountType'] as String?) ?? 'savings',
      currency: ((json['currency'] as String?) ?? 'NOK').toUpperCase(),
      openingBalance: _asDouble(json['openingBalance']),
      balanceAsOf: _parseDate(json['balanceAsOf']),
      familyVisibility: (json['familyVisibility'] as String?) ?? 'private',
      notes: (json['notes'] as String?) ?? '',
      archived: json['archived'] as bool? ?? false,
      archivedAt: _parseDate(json['archivedAt']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
