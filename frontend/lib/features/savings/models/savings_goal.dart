class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.targetCurrency,
    required this.sourceCurrency,
    required this.monthlyTargetAmount,
    required this.startMonth,
    required this.targetDate,
    required this.totalSavedAmount,
    required this.totalSourceAmount,
    required this.remainingAmount,
    required this.progress,
    required this.currentMonthSavedAmount,
    required this.contributionCount,
    required this.lastContributionAt,
    required this.notes,
    required this.archived,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final double targetAmount;
  final String targetCurrency;
  final String sourceCurrency;
  final double monthlyTargetAmount;
  final String startMonth;
  final DateTime? targetDate;
  final double totalSavedAmount;
  final double totalSourceAmount;
  final double remainingAmount;
  final double progress;
  final double currentMonthSavedAmount;
  final int contributionCount;
  final DateTime? lastContributionAt;
  final String notes;
  final bool archived;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SavingsGoal.fromJson(Map<String, dynamic> json) {
    return SavingsGoal(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      targetAmount: _asDouble(json['targetAmount']),
      targetCurrency: ((json['targetCurrency'] as String?) ?? 'INR')
          .toUpperCase(),
      sourceCurrency: ((json['sourceCurrency'] as String?) ?? 'NOK')
          .toUpperCase(),
      monthlyTargetAmount: _asDouble(json['monthlyTargetAmount']),
      startMonth: (json['startMonth'] as String?) ?? '',
      targetDate: _parseDate(json['targetDate']),
      totalSavedAmount: _asDouble(json['totalSavedAmount']),
      totalSourceAmount: _asDouble(json['totalSourceAmount']),
      remainingAmount: _asDouble(json['remainingAmount']),
      progress: _asDouble(json['progress']),
      currentMonthSavedAmount: _asDouble(json['currentMonthSavedAmount']),
      contributionCount: _asInt(json['contributionCount']),
      lastContributionAt: _parseDate(json['lastContributionAt']),
      notes: (json['notes'] as String?) ?? '',
      archived: json['archived'] as bool? ?? false,
      archivedAt: _parseDate(json['archivedAt']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  SavingsGoal copyWith({
    String? id,
    String? name,
    double? targetAmount,
    String? targetCurrency,
    String? sourceCurrency,
    double? monthlyTargetAmount,
    String? startMonth,
    DateTime? targetDate,
    double? totalSavedAmount,
    double? totalSourceAmount,
    double? remainingAmount,
    double? progress,
    double? currentMonthSavedAmount,
    int? contributionCount,
    DateTime? lastContributionAt,
    String? notes,
    bool? archived,
    DateTime? archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SavingsGoal(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      targetCurrency: targetCurrency ?? this.targetCurrency,
      sourceCurrency: sourceCurrency ?? this.sourceCurrency,
      monthlyTargetAmount: monthlyTargetAmount ?? this.monthlyTargetAmount,
      startMonth: startMonth ?? this.startMonth,
      targetDate: targetDate ?? this.targetDate,
      totalSavedAmount: totalSavedAmount ?? this.totalSavedAmount,
      totalSourceAmount: totalSourceAmount ?? this.totalSourceAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      progress: progress ?? this.progress,
      currentMonthSavedAmount:
          currentMonthSavedAmount ?? this.currentMonthSavedAmount,
      contributionCount: contributionCount ?? this.contributionCount,
      lastContributionAt: lastContributionAt ?? this.lastContributionAt,
      notes: notes ?? this.notes,
      archived: archived ?? this.archived,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class SavingsContribution {
  const SavingsContribution({
    required this.id,
    required this.goalId,
    required this.sourceAmount,
    required this.sourceCurrency,
    required this.targetAmount,
    required this.targetCurrency,
    required this.feeAmount,
    required this.feeCurrency,
    required this.exchangeRate,
    required this.marketRate,
    required this.marketTargetAmount,
    required this.exchangeRateProvider,
    required this.exchangeRateFetchedAt,
    required this.exchangeRateAsOf,
    required this.date,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String goalId;
  final double sourceAmount;
  final String sourceCurrency;
  final double targetAmount;
  final String targetCurrency;
  final double feeAmount;
  final String feeCurrency;
  final double exchangeRate;
  final double marketRate;
  final double marketTargetAmount;
  final String exchangeRateProvider;
  final DateTime? exchangeRateFetchedAt;
  final DateTime? exchangeRateAsOf;
  final DateTime date;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SavingsContribution.fromJson(Map<String, dynamic> json) {
    return SavingsContribution(
      id: (json['id'] as String?) ?? '',
      goalId: (json['goalId'] as String?) ?? '',
      sourceAmount: _asDouble(json['sourceAmount']),
      sourceCurrency: ((json['sourceCurrency'] as String?) ?? 'NOK')
          .toUpperCase(),
      targetAmount: _asDouble(json['targetAmount']),
      targetCurrency: ((json['targetCurrency'] as String?) ?? 'INR')
          .toUpperCase(),
      feeAmount: _asDouble(json['feeAmount']),
      feeCurrency: ((json['feeCurrency'] as String?) ?? 'NOK').toUpperCase(),
      exchangeRate: _asDouble(json['exchangeRate']),
      marketRate: _asDouble(json['marketRate']),
      marketTargetAmount: _asDouble(json['marketTargetAmount']),
      exchangeRateProvider: (json['exchangeRateProvider'] as String?) ?? '',
      exchangeRateFetchedAt: _parseDate(json['exchangeRateFetchedAt']),
      exchangeRateAsOf: _parseDate(json['exchangeRateAsOf']),
      date: _parseDate(json['date']) ?? DateTime.now(),
      notes: (json['notes'] as String?) ?? '',
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }
}

class SavingsContributionResult {
  const SavingsContributionResult({
    required this.goal,
    required this.contribution,
  });

  final SavingsGoal goal;
  final SavingsContribution contribution;

  factory SavingsContributionResult.fromJson(Map<String, dynamic> json) {
    return SavingsContributionResult(
      goal: SavingsGoal.fromJson(
        json['goal'] is Map<String, dynamic>
            ? json['goal'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
      contribution: SavingsContribution.fromJson(
        json['contribution'] is Map<String, dynamic>
            ? json['contribution'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
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

DateTime? _parseDate(Object? value) {
  final raw = value?.toString() ?? '';
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
