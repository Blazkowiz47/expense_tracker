class GroupExpense {
  const GroupExpense({
    required this.id,
    required this.groupId,
    required this.createdBy,
    required this.updatedBy,
    required this.paidBy,
    required this.splitMode,
    required this.splitWith,
    this.splitAmounts = const {},
    this.splitAmountsByCurrency = const {},
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
  final Map<String, double> splitAmounts;
  final Map<String, Map<String, double>> splitAmountsByCurrency;
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
      splitAmounts: _parseAmountMap(json['splitAmounts']),
      splitAmountsByCurrency: _parseAmountsByCurrency(
        json['splitAmountsByCurrency'],
      ),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: _normalizeCurrency(json['currency']),
      convertedAmounts: _parseAmountMap(
        json['convertedAmounts'],
        normalizeCurrencyKeys: true,
      ),
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

  Map<String, double> splitAmountsForCurrency(String targetCurrency) {
    final normalized = _normalizeCurrency(targetCurrency);
    final saved = splitAmountsByCurrency[normalized];
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
    if (splitAmounts.isEmpty || amount <= 0) {
      return const {};
    }
    final currencyAmount = amountsByCurrency[normalized];
    if (currencyAmount == null) {
      return normalized == currency ? splitAmounts : const {};
    }
    final ratio = currencyAmount / amount;
    return Map.unmodifiable(
      splitAmounts.map((key, value) => MapEntry(key, value * ratio)),
    );
  }
}

String _normalizeCurrency(Object? value) {
  final currency = value?.toString().trim().toUpperCase() ?? '';
  return RegExp(r'^[A-Z]{3}$').hasMatch(currency) ? currency : 'INR';
}

Map<String, double> _parseAmountMap(
  Object? value, {
  bool normalizeCurrencyKeys = false,
}) {
  if (value is! Map) {
    return const {};
  }
  final amounts = <String, double>{};
  for (final entry in value.entries) {
    final key = normalizeCurrencyKeys
        ? _normalizeCurrency(entry.key)
        : (entry.key?.toString().trim() ?? '');
    if (key.isEmpty) continue;
    final rawAmount = entry.value is Map
        ? (entry.value as Map)['amount']
        : entry.value;
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse(rawAmount?.toString() ?? '');
    if (amount != null) {
      amounts[key] = amount;
    }
  }
  return Map.unmodifiable(amounts);
}

Map<String, Map<String, double>> _parseAmountsByCurrency(Object? value) {
  if (value is! Map) {
    return const {};
  }
  final amounts = <String, Map<String, double>>{};
  for (final entry in value.entries) {
    final currency = _normalizeCurrency(entry.key);
    final currencyAmounts = _parseAmountMap(entry.value);
    if (currencyAmounts.isNotEmpty) {
      amounts[currency] = currencyAmounts;
    }
  }
  return Map.unmodifiable(amounts);
}
