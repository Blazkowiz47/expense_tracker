import 'package:expense_tracker/features/groups/models/group_expense.dart';

typedef GroupLentBorrowed = ({double lent, double borrowed});

Map<String, GroupLentBorrowed> calculateGroupLentBorrowedByCurrency({
  required List<GroupExpense> expenses,
  required int memberCount,
  required Set<String> userIdentifiers,
}) {
  final result = <String, GroupLentBorrowed>{};
  for (final expense in expenses) {
    for (final entry in expense.amountsByCurrency.entries) {
      final currencyExpense = GroupExpense(
        id: expense.id,
        groupId: expense.groupId,
        createdBy: expense.createdBy,
        updatedBy: expense.updatedBy,
        paidBy: expense.paidBy,
        splitMode: expense.splitMode,
        splitWith: expense.splitWith,
        splitAmounts: expense.splitAmountsForCurrency(entry.key),
        amount: entry.value,
        currency: entry.key,
        category: expense.category,
        description: expense.description,
        attachments: expense.attachments,
        date: expense.date,
        createdAt: expense.createdAt,
        updatedAt: expense.updatedAt,
      );
      final balance = calculateGroupLentBorrowed(
        expenses: [currencyExpense],
        memberCount: memberCount,
        userIdentifiers: userIdentifiers,
      );
      final current = result[entry.key] ?? (lent: 0.0, borrowed: 0.0);
      result[entry.key] = (
        lent: current.lent + balance.lent,
        borrowed: current.borrowed + balance.borrowed,
      );
    }
  }
  return result;
}

GroupLentBorrowed calculateGroupLentBorrowed({
  required List<GroupExpense> expenses,
  required int memberCount,
  required Set<String> userIdentifiers,
}) {
  if (memberCount <= 0 || userIdentifiers.isEmpty) {
    return (lent: 0, borrowed: 0);
  }

  final normalizedIds = userIdentifiers
      .map((id) => id.trim().toLowerCase())
      .where((id) => id.isNotEmpty)
      .toSet();
  if (normalizedIds.isEmpty) {
    return (lent: 0, borrowed: 0);
  }

  var lent = 0.0;
  var borrowed = 0.0;
  for (final expense in expenses) {
    if (expense.amount <= 0) continue;
    final paidBy =
        (expense.paidBy.isNotEmpty ? expense.paidBy : expense.createdBy)
            .trim()
            .toLowerCase();
    final splitAmounts = _normalizedSplitAmounts(expense.splitAmounts);
    if (splitAmounts.isNotEmpty) {
      final userShare = splitAmounts.entries
          .where((entry) => normalizedIds.contains(entry.key))
          .fold<double>(0, (sum, entry) => sum + entry.value);
      if (normalizedIds.contains(paidBy)) {
        lent += expense.amount - userShare;
      } else {
        borrowed += userShare;
      }
      continue;
    }

    final splitParticipants = expense.splitWith
        .map((id) => id.trim().toLowerCase())
        .where((id) => id.isNotEmpty)
        .toSet();
    final splitCount = splitParticipants.isEmpty
        ? memberCount
        : splitParticipants.length;
    final splitShare = expense.amount / splitCount;
    final userIsInSplit =
        splitParticipants.isEmpty ||
        splitParticipants.any((id) => normalizedIds.contains(id));
    if (normalizedIds.contains(paidBy)) {
      lent += expense.amount - (userIsInSplit ? splitShare : 0);
    } else if (userIsInSplit) {
      borrowed += splitShare;
    }
  }

  return (lent: lent, borrowed: borrowed);
}

Map<String, double> _normalizedSplitAmounts(Map<String, double> amounts) {
  final normalized = <String, double>{};
  for (final entry in amounts.entries) {
    final key = entry.key.trim().toLowerCase();
    if (key.isEmpty || entry.value <= 0) continue;
    normalized[key] = (normalized[key] ?? 0) + entry.value;
  }
  return normalized;
}
