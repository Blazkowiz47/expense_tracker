import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/utils/group_balance_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GroupExpense expense({
    required String id,
    required String createdBy,
    required double amount,
  }) {
    final now = DateTime(2026, 2, 28);
    return GroupExpense(
      id: id,
      groupId: 'g1',
      createdBy: createdBy,
      amount: amount,
      description: id,
      attachments: const [],
      date: now,
      createdAt: now,
    );
  }

  test('returns zero balance for empty identifiers', () {
    final result = calculateGroupLentBorrowed(
      expenses: [expense(id: 'e1', createdBy: 'u1', amount: 120)],
      memberCount: 2,
      userIdentifiers: const {},
    );

    expect(result.lent, 0);
    expect(result.borrowed, 0);
  });

  test('calculates owed amount when current user paid', () {
    final result = calculateGroupLentBorrowed(
      expenses: [
        expense(id: 'e1', createdBy: 'u1', amount: 120),
        expense(id: 'e2', createdBy: 'u1', amount: 80),
      ],
      memberCount: 2,
      userIdentifiers: const {'u1'},
    );

    expect(result.lent, 100);
    expect(result.borrowed, 0);
  });

  test('calculates owed amount when someone else paid', () {
    final result = calculateGroupLentBorrowed(
      expenses: [expense(id: 'e1', createdBy: 'u2', amount: 300)],
      memberCount: 3,
      userIdentifiers: const {'u1'},
    );

    expect(result.lent, 0);
    expect(result.borrowed, 100);
  });

  test('uses all identifiers for matching createdBy', () {
    final result = calculateGroupLentBorrowed(
      expenses: [expense(id: 'e1', createdBy: 'test@example.com', amount: 90)],
      memberCount: 3,
      userIdentifiers: const {'u1', 'test@example.com'},
    );

    expect(result.lent, 60);
    expect(result.borrowed, 0);
  });

  test('calculates mixed lending and borrowing correctly', () {
    final result = calculateGroupLentBorrowed(
      expenses: [
        expense(id: 'e1', createdBy: 'u1', amount: 150),
        expense(id: 'e2', createdBy: 'u2', amount: 90),
      ],
      memberCount: 3,
      userIdentifiers: const {'u1'},
    );

    expect(result.lent, 100);
    expect(result.borrowed, 30);
  });
}
