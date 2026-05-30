class MonthlyPlan {
  const MonthlyPlan({
    required this.month,
    required this.currency,
    required this.totalBudget,
    required this.totalActual,
    required this.totalRemaining,
    required this.categories,
  });

  final String month;
  final String currency;
  final double totalBudget;
  final double totalActual;
  final double totalRemaining;
  final List<MonthlyPlanCategory> categories;

  factory MonthlyPlan.fromJson(Map<String, dynamic> json) {
    return MonthlyPlan(
      month: (json['month'] ?? '').toString(),
      currency: (json['currency'] ?? 'INR').toString(),
      totalBudget: (json['totalBudget'] as num?)?.toDouble() ?? 0,
      totalActual: (json['totalActual'] as num?)?.toDouble() ?? 0,
      totalRemaining: (json['totalRemaining'] as num?)?.toDouble() ?? 0,
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
  });

  final String category;
  final double budget;
  final double actual;
  final double remaining;
  final double progress;
  final bool overBudget;

  factory MonthlyPlanCategory.fromJson(Map<String, dynamic> json) {
    return MonthlyPlanCategory(
      category: (json['category'] ?? '').toString(),
      budget: (json['budget'] as num?)?.toDouble() ?? 0,
      actual: (json['actual'] as num?)?.toDouble() ?? 0,
      remaining: (json['remaining'] as num?)?.toDouble() ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      overBudget: json['overBudget'] as bool? ?? false,
    );
  }
}
