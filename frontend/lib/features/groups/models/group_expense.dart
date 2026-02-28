class GroupExpense {
  const GroupExpense({
    required this.id,
    required this.groupId,
    required this.createdBy,
    required this.paidBy,
    required this.splitMode,
    required this.splitWith,
    required this.amount,
    required this.description,
    required this.attachments,
    required this.date,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String createdBy;
  final String paidBy;
  final String splitMode;
  final List<String> splitWith;
  final double amount;
  final String description;
  final List<String> attachments;
  final DateTime date;
  final DateTime createdAt;

  factory GroupExpense.fromJson(Map<String, dynamic> json) {
    return GroupExpense(
      id: (json['id'] as String?) ?? '',
      groupId: (json['groupId'] as String?) ?? '',
      createdBy: (json['createdBy'] as String?) ?? '',
      paidBy: (json['paidBy'] as String?) ?? '',
      splitMode: (json['splitMode'] as String?) ?? 'equally',
      splitWith: (json['splitWith'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      description: (json['description'] as String?) ?? '',
      attachments: (json['attachments'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      date:
          DateTime.tryParse((json['date'] as String?) ?? '') ?? DateTime.now(),
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
