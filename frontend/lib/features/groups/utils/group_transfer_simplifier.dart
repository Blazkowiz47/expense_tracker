class GroupTransferSuggestion {
  const GroupTransferSuggestion({
    required this.fromUid,
    required this.toUid,
    required this.amount,
  });

  final String fromUid;
  final String toUid;
  final double amount;
}

List<GroupTransferSuggestion> simplifyGroupTransfers(
  Map<String, double> memberNetByUid,
) {
  const epsilon = 0.005;
  final creditors = <_BalanceNode>[];
  final debtors = <_BalanceNode>[];

  memberNetByUid.forEach((uid, net) {
    final key = uid.trim();
    if (key.isEmpty) return;
    if (net > epsilon) {
      creditors.add(_BalanceNode(uid: key, amount: net));
    } else if (net < -epsilon) {
      debtors.add(_BalanceNode(uid: key, amount: -net));
    }
  });

  creditors.sort((a, b) => b.amount.compareTo(a.amount));
  debtors.sort((a, b) => b.amount.compareTo(a.amount));

  final suggestions = <GroupTransferSuggestion>[];
  var creditorIndex = 0;
  var debtorIndex = 0;

  while (creditorIndex < creditors.length && debtorIndex < debtors.length) {
    final creditor = creditors[creditorIndex];
    final debtor = debtors[debtorIndex];
    final amount = creditor.amount < debtor.amount
        ? creditor.amount
        : debtor.amount;
    if (amount > epsilon) {
      suggestions.add(
        GroupTransferSuggestion(
          fromUid: debtor.uid,
          toUid: creditor.uid,
          amount: amount,
        ),
      );
    }

    creditor.amount -= amount;
    debtor.amount -= amount;

    if (creditor.amount <= epsilon) {
      creditorIndex++;
    }
    if (debtor.amount <= epsilon) {
      debtorIndex++;
    }
  }

  return suggestions;
}

class _BalanceNode {
  _BalanceNode({required this.uid, required this.amount});

  final String uid;
  double amount;
}
