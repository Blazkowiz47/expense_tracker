class FriendSettlement {
  const FriendSettlement({
    required this.id,
    required this.uids,
    required this.payerUid,
    required this.receiverUid,
    required this.amount,
    required this.currency,
    required this.date,
    required this.createdAt,
    this.note = '',
    this.createdBy = '',
    this.updatedAt,
  });

  final String id;
  final List<String> uids;
  final String payerUid;
  final String receiverUid;
  final double amount;
  final String currency;
  final String note;
  final String createdBy;
  final DateTime date;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory FriendSettlement.fromJson(Map<String, dynamic> json) {
    return FriendSettlement(
      id: (json['id'] as String?) ?? '',
      uids: (json['uids'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      payerUid: (json['payerUid'] as String?) ?? '',
      receiverUid: (json['receiverUid'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: _normalizeCurrency(json['currency']),
      note: (json['note'] as String?) ?? '',
      createdBy: (json['createdBy'] as String?) ?? '',
      date:
          DateTime.tryParse((json['date'] as String?) ?? '') ??
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? ''),
    );
  }
}

String _normalizeCurrency(Object? value) {
  final currency = value?.toString().trim().toUpperCase() ?? '';
  return RegExp(r'^[A-Z]{3}$').hasMatch(currency) ? currency : 'INR';
}
