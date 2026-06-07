import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/utils/group_balance_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GroupExpense expense({
    required String id,
    required String createdBy,
    required double amount,
    List<String> splitWith = const [],
    Map<String, double> splitAmounts = const {},
    Map<String, double> convertedAmounts = const {},
    Map<String, Map<String, double>> splitAmountsByCurrency = const {},
  }) {
    final now = DateTime(2026, 2, 28);
    return GroupExpense(
      id: id,
      groupId: 'g1',
      createdBy: createdBy,
      updatedBy: createdBy,
      paidBy: createdBy,
      splitMode: 'equally',
      splitWith: splitWith,
      splitAmounts: splitAmounts,
      splitAmountsByCurrency: splitAmountsByCurrency,
      amount: amount,
      convertedAmounts: convertedAmounts,
      description: id,
      attachments: const [],
      date: now,
      createdAt: now,
      updatedAt: now,
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

  test('honors custom split participants', () {
    final result = calculateGroupLentBorrowed(
      expenses: [
        expense(id: 'e1', createdBy: 'u2', amount: 90, splitWith: const ['u1']),
        expense(id: 'e2', createdBy: 'u1', amount: 60, splitWith: const ['u2']),
      ],
      memberCount: 3,
      userIdentifiers: const {'u1'},
    );

    expect(result.lent, 60);
    expect(result.borrowed, 90);
  });

  test('honors exact split amounts', () {
    final result = calculateGroupLentBorrowed(
      expenses: [
        expense(
          id: 'e1',
          createdBy: 'u2',
          amount: 90,
          splitAmounts: const {'u1': 20, 'u2': 10, 'u3': 60},
        ),
      ],
      memberCount: 3,
      userIdentifiers: const {'u1'},
    );

    expect(result.lent, 0);
    expect(result.borrowed, 20);
  });

  test('honors converted split amounts by currency', () {
    final result = calculateGroupLentBorrowedByCurrency(
      expenses: [
        expense(
          id: 'e1',
          createdBy: 'u2',
          amount: 10,
          convertedAmounts: const {'USD': 10, 'NOK': 100},
          splitAmounts: const {'u1': 2, 'u2': 8},
          splitAmountsByCurrency: const {
            'USD': {'u1': 2, 'u2': 8},
            'NOK': {'u1': 20, 'u2': 80},
          },
        ),
      ],
      memberCount: 2,
      userIdentifiers: const {'u1'},
    );

    expect(result['USD']?.borrowed, 2);
    expect(result['NOK']?.borrowed, 20);
  });
}
