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
  final byCurrency = calculateFriendSettlementNetByUidAndCurrency(expenses);
  return byCurrency.map(
    (uid, amounts) => MapEntry(
      uid,
      amounts.values.fold<double>(0, (sum, amount) => sum + amount),
    ),
  );
}

Map<String, Map<String, double>> calculateFriendSettlementNetByUidAndCurrency(
  List<Expense> expenses,
) {
  final netByCurrency = <String, Map<String, double>>{};
  for (final expense in expenses) {
    final category = (expense.category ?? '').trim().toLowerCase();
    if (category != 'settlement') continue;
    final meta = parseFriendSettlementMeta(expense.description ?? '');
    if (meta == null) continue;
    final signed = meta.direction == 'received'
        ? expense.amount
        : -expense.amount;
    final currency = _normalizeCurrency(expense.currency);
    final friendAmounts = netByCurrency.putIfAbsent(meta.uid, () => {});
    friendAmounts[currency] = (friendAmounts[currency] ?? 0) + signed;
  }
  return netByCurrency;
}

String _normalizeCurrency(String? value) {
  final currency = value?.trim().toUpperCase() ?? '';
  return RegExp(r'^[A-Z]{3}$').hasMatch(currency) ? currency : 'INR';
}
