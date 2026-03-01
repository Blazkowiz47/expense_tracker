import 'package:expense_tracker/data/models/expense.dart';

class SettlementMeta {
  const SettlementMeta({required this.uid, required this.direction});

  final String uid;
  final String direction;
}

SettlementMeta? parseFriendSettlementMeta(String description) {
  final match = RegExp(
    r'\[uid:([^\]]+)\]\[dir:(paid|received)\]',
  ).firstMatch(description);
  if (match == null) return null;
  final uid = (match.group(1) ?? '').trim();
  final direction = (match.group(2) ?? '').trim();
  if (uid.isEmpty) return null;
  if (direction != 'paid' && direction != 'received') return null;
  return SettlementMeta(uid: uid, direction: direction);
}

Map<String, double> calculateFriendSettlementNetByUid(List<Expense> expenses) {
  final netByUid = <String, double>{};
  for (final expense in expenses) {
    final category = (expense.category ?? '').trim().toLowerCase();
    if (category != 'settlement') continue;
    final meta = parseFriendSettlementMeta(expense.description ?? '');
    if (meta == null) continue;
    final signed = meta.direction == 'received'
        ? expense.amount
        : -expense.amount;
    netByUid.update(
      meta.uid,
      (value) => value + signed,
      ifAbsent: () => signed,
    );
  }
  return netByUid;
}
