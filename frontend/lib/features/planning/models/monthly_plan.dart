class MonthlyPlan {
  const MonthlyPlan({
    required this.month,
    this.groupId,
    required this.currency,
    required this.totalBudget,
    required this.totalActual,
    required this.totalRemaining,
    this.income,
    this.surplus,
    this.convertedExpenseCount = 0,
    this.excludedExpenseCount = 0,
    this.excludedActualsByCurrency = const {},
    required this.categories,
  });

  final String month;
  final String? groupId;
  final String currency;
  final double totalBudget;
  final double totalActual;
  final double totalRemaining;
  final double? income;
  final double? surplus;
  final int convertedExpenseCount;
  final int excludedExpenseCount;
  final Map<String, double> excludedActualsByCurrency;
  final List<MonthlyPlanCategory> categories;

  factory MonthlyPlan.fromJson(Map<String, dynamic> json) {
    final metadata = json['actualsMetadata'] is Map
        ? json['actualsMetadata'] as Map
        : const {};
    return MonthlyPlan(
      month: (json['month'] ?? '').toString(),
      groupId: (json['groupId'] as String?)?.trim().isNotEmpty == true
          ? (json['groupId'] as String).trim()
          : null,
      currency: (json['currency'] ?? 'INR').toString(),
      totalBudget: (json['totalBudget'] as num?)?.toDouble() ?? 0,
      totalActual: (json['totalActual'] as num?)?.toDouble() ?? 0,
      totalRemaining: (json['totalRemaining'] as num?)?.toDouble() ?? 0,
      income:
          _parseDouble(json['totalIncome']) ??
          _parseDouble(json['monthlyIncome']) ??
          _parseDouble(json['plannedIncome']) ??
          _parseDouble(json['projectedIncome']) ??
          _parseDouble(json['income']),
      surplus:
          _parseDouble(json['totalSurplus']) ??
          _parseDouble(json['projectedSurplus']) ??
          _parseDouble(json['netSurplus']) ??
          _parseDouble(json['surplus']),
      convertedExpenseCount:
          _parseInt(json['convertedExpenseCount']) ??
          _parseInt(metadata['convertedExpenseCount']) ??
          0,
      excludedExpenseCount:
          _parseInt(json['excludedExpenseCount']) ??
          _parseInt(json['skippedActualExpenseCount']) ??
          _parseInt(metadata['uncountedExpenseCount']) ??
          0,
      excludedActualsByCurrency:
          _parseAmountMap(json['excludedActualsByCurrency']) ??
          _parseAmountMap(metadata['uncountedSpendByCurrency']) ??
          const {},
      categories: (json['categories'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MonthlyPlanCategory.fromJson)
          .toList(growable: false),
    );
  }

  Map<String, double> get budgetsByCategory => {
    for (final item in categories) item.category: item.budget,
  };
}

class MonthlyPlanCategory {
  const MonthlyPlanCategory({
    required this.category,
    required this.budget,
    required this.actual,
    required this.remaining,
    required this.progress,
    required this.overBudget,
    this.convertedExpenseCount = 0,
    this.excludedExpenseCount = 0,
    this.excludedActualsByCurrency = const {},
  });

  final String category;
  final double budget;
  final double actual;
  final double remaining;
  final double progress;
  final bool overBudget;
  final int convertedExpenseCount;
  final int excludedExpenseCount;
  final Map<String, double> excludedActualsByCurrency;

  factory MonthlyPlanCategory.fromJson(Map<String, dynamic> json) {
    return MonthlyPlanCategory(
      category: (json['category'] ?? '').toString(),
      budget: (json['budget'] as num?)?.toDouble() ?? 0,
      actual: (json['actual'] as num?)?.toDouble() ?? 0,
      remaining: (json['remaining'] as num?)?.toDouble() ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      overBudget: json['overBudget'] as bool? ?? false,
      convertedExpenseCount: _parseInt(json['convertedExpenseCount']) ?? 0,
      excludedExpenseCount:
          _parseInt(json['excludedExpenseCount']) ??
          _parseInt(json['skippedActualExpenseCount']) ??
          0,
      excludedActualsByCurrency:
          _parseAmountMap(json['excludedActualsByCurrency']) ?? const {},
    );
  }
}

double? _parseDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

int? _parseInt(Object? value) {
  return value is num ? value.toInt() : null;
}

Map<String, double>? _parseAmountMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final amounts = <String, double>{};
  for (final entry in value.entries) {
    final currency = entry.key.toString().trim().toUpperCase();
    if (currency.isEmpty) {
      continue;
    }
    final amount = entry.value;
    if (amount is num) {
      amounts[currency] = amount.toDouble();
    }
  }
  return Map.unmodifiable(amounts);
}
