import 'package:expense_tracker/features/groups/models/group_expense.dart';

typedef GroupLentBorrowed = ({double lent, double borrowed});

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
    final paidBy =
        (expense.paidBy.isNotEmpty ? expense.paidBy : expense.createdBy)
            .trim()
            .toLowerCase();
    if (normalizedIds.contains(paidBy)) {
      lent += expense.amount - (userIsInSplit ? splitShare : 0);
    } else if (userIsInSplit) {
      borrowed += splitShare;
    }
  }

  return (lent: lent, borrowed: borrowed);
}
