class RecurringTemplate {
  const RecurringTemplate({
    required this.id,
    required this.title,
    required this.kind,
    required this.amount,
    required this.currency,
    required this.category,
    required this.frequency,
    required this.dayOfMonth,
    required this.startDate,
    required this.nextDueDate,
    required this.active,
  });

  final String id;
  final String title;
  final String kind;
  final double amount;
  final String currency;
  final String category;
  final String frequency;
  final int dayOfMonth;
  final DateTime startDate;
  final DateTime nextDueDate;
  final bool active;

  factory RecurringTemplate.fromJson(Map<String, dynamic> json) {
    return RecurringTemplate(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'expense',
      amount:
          (json['expectedAmount'] as num?)?.toDouble() ??
          (json['amount'] as num?)?.toDouble() ??
          0,
      currency: (json['currency'] as String?) ?? 'INR',
      category: (json['category'] as String?) ?? '',
      frequency: (json['frequency'] as String?) ?? '',
      dayOfMonth: (json['dayOfMonth'] as num?)?.toInt() ?? 1,
      startDate:
          DateTime.tryParse((json['startDate'] as String?) ?? '') ??
          DateTime.now(),
      nextDueDate:
          DateTime.tryParse((json['nextDueDate'] as String?) ?? '') ??
          DateTime.now(),
      active: json['active'] as bool? ?? true,
    );
  }
}

class RecurringOccurrence {
  const RecurringOccurrence({
    required this.id,
    required this.templateId,
    required this.period,
    required this.kind,
    required this.title,
    required this.category,
    required this.currency,
    required this.expectedAmount,
    required this.actualAmount,
    required this.dueDate,
    required this.actualDate,
    required this.status,
  });

  final String id;
  final String templateId;
  final String period;
  final String kind;
  final String title;
  final String category;
  final String currency;
  final double expectedAmount;
  final double? actualAmount;
  final DateTime dueDate;
  final DateTime? actualDate;
  final String status;

  bool get isIncome => kind == 'income';
  bool get isConfirmed => status == 'confirmed';

  factory RecurringOccurrence.fromJson(Map<String, dynamic> json) {
    return RecurringOccurrence(
      id: (json['id'] as String?) ?? '',
      templateId: (json['templateId'] as String?) ?? '',
      period: (json['period'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'expense',
      title: (json['title'] as String?) ?? '',
      category: (json['category'] as String?) ?? '',
      currency: (json['currency'] as String?) ?? 'INR',
      expectedAmount: (json['expectedAmount'] as num?)?.toDouble() ?? 0,
      actualAmount: (json['actualAmount'] as num?)?.toDouble(),
      dueDate:
          DateTime.tryParse((json['dueDate'] as String?) ?? '') ??
          DateTime.now(),
      actualDate: DateTime.tryParse((json['actualDate'] as String?) ?? ''),
      status: (json['status'] as String?) ?? 'expected',
    );
  }
}
