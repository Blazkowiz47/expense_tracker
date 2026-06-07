class GroupExpense {
  const GroupExpense({
    required this.id,
    required this.groupId,
    required this.createdBy,
    required this.updatedBy,
    required this.paidBy,
    required this.splitMode,
    required this.splitWith,
    required this.amount,
    this.currency = 'INR',
    this.convertedAmounts = const {},
    this.category = '',
    required this.description,
    required this.attachments,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String groupId;
  final String createdBy;
  final String updatedBy;
  final String paidBy;
  final String splitMode;
  final List<String> splitWith;
  final double amount;
  final String currency;
  final Map<String, double> convertedAmounts;
  final String category;
  final String description;
  final List<String> attachments;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory GroupExpense.fromJson(Map<String, dynamic> json) {
    return GroupExpense(
      id: (json['id'] as String?) ?? '',
      groupId: (json['groupId'] as String?) ?? '',
      createdBy: (json['createdBy'] as String?) ?? '',
      updatedBy: (json['updatedBy'] as String?) ?? '',
      paidBy: (json['paidBy'] as String?) ?? '',
      splitMode: (json['splitMode'] as String?) ?? 'equally',
      splitWith: (json['splitWith'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: _normalizeCurrency(json['currency']),
      convertedAmounts: _parseConvertedAmounts(json['convertedAmounts']),
      category: (json['category'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      attachments: (json['attachments'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      date:
          DateTime.tryParse((json['date'] as String?) ?? '') ?? DateTime.now(),
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, double> get amountsByCurrency {
    if (convertedAmounts.isNotEmpty) {
      return convertedAmounts;
    }
    return {currency: amount};
  }
}

String _normalizeCurrency(Object? value) {
  final currency = value?.toString().trim().toUpperCase() ?? '';
  return RegExp(r'^[A-Z]{3}$').hasMatch(currency) ? currency : 'INR';
}

Map<String, double> _parseConvertedAmounts(Object? value) {
  if (value is! Map) {
    return const {};
  }
  final amounts = <String, double>{};
  for (final entry in value.entries) {
    final currency = _normalizeCurrency(entry.key);
    final rawAmount = entry.value is Map
        ? (entry.value as Map)['amount']
        : entry.value;
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse(rawAmount?.toString() ?? '');
    if (amount != null) {
      amounts[currency] = amount;
    }
  }
  return Map.unmodifiable(amounts);
}
