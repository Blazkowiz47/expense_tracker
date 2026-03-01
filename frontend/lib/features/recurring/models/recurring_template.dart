class RecurringTemplate {
  const RecurringTemplate({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.frequency,
    required this.startDate,
    required this.nextDueDate,
    required this.active,
  });

  final String id;
  final String title;
  final double amount;
  final String category;
  final String frequency;
  final DateTime startDate;
  final DateTime nextDueDate;
  final bool active;

  factory RecurringTemplate.fromJson(Map<String, dynamic> json) {
    return RecurringTemplate(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      category: (json['category'] as String?) ?? '',
      frequency: (json['frequency'] as String?) ?? '',
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
