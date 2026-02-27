class GroupExpense {
  const GroupExpense({
    required this.id,
    required this.groupId,
    required this.createdBy,
    required this.amount,
    required this.description,
    required this.date,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String createdBy;
  final double amount;
  final String description;
  final DateTime date;
  final DateTime createdAt;

  factory GroupExpense.fromJson(Map<String, dynamic> json) {
    return GroupExpense(
      id: (json['id'] as String?) ?? '',
      groupId: (json['groupId'] as String?) ?? '',
      createdBy: (json['createdBy'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      description: (json['description'] as String?) ?? '',
      date:
          DateTime.tryParse((json['date'] as String?) ?? '') ?? DateTime.now(),
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
