class GroupSettlement {
  const GroupSettlement({
    required this.id,
    required this.groupId,
    required this.payerUid,
    required this.receiverUid,
    required this.amount,
    this.currency = 'INR',
    this.note = '',
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String payerUid;
  final String receiverUid;
  final double amount;
  final String currency;
  final String note;
  final String createdBy;
  final DateTime createdAt;

  factory GroupSettlement.fromJson(Map<String, dynamic> json) {
    return GroupSettlement(
      id: (json['id'] as String?) ?? '',
      groupId: (json['groupId'] as String?) ?? '',
      payerUid: (json['payerUid'] as String?) ?? '',
      receiverUid: (json['receiverUid'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: _normalizeCurrency(json['currency']),
      note: (json['note'] as String?) ?? '',
      createdBy: (json['createdBy'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

String _normalizeCurrency(Object? value) {
  final currency = value?.toString().trim().toUpperCase() ?? '';
  return RegExp(r'^[A-Z]{3}$').hasMatch(currency) ? currency : 'INR';
}
