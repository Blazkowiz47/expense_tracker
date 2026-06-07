import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/features/friends/utils/settlement_balance_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Expense buildExpense({
    required String id,
    required double amount,
    required String category,
    required String description,
    String currency = 'INR',
  }) {
    return Expense(
      core: ExpenseCore(
        id: id,
        title: 'x',
        amount: amount,
        currency: currency,
        category: category,
        createdAt: DateTime.parse('2026-03-01T00:00:00Z'),
      ),
      description: description,
    );
  }

  group('parseFriendSettlementMeta', () {
    test('parses valid metadata', () {
      final meta = parseFriendSettlementMeta(
        'Settle up [uid:user-1][dir:paid]',
      );
      expect(meta, isNotNull);
      expect(meta!.uid, 'user-1');
      expect(meta.direction, 'paid');
    });

    test('returns null for invalid payload', () {
      expect(parseFriendSettlementMeta('hello world'), isNull);
      expect(parseFriendSettlementMeta('[uid:x][dir:unknown]'), isNull);
      expect(parseFriendSettlementMeta('[uid:][dir:paid]'), isNull);
    });
  });

  group('calculateFriendSettlementNetByUid', () {
    test('aggregates paid and received amounts per uid', () {
      final expenses = [
        buildExpense(
          id: '1',
          amount: 100,
          category: 'Settlement',
          description: 'A [uid:u1][dir:paid]',
        ),
        buildExpense(
          id: '2',
          amount: 40,
          category: 'Settlement',
          description: 'B [uid:u1][dir:received]',
        ),
        buildExpense(
          id: '3',
          amount: 60,
          category: 'Settlement',
          description: 'C [uid:u2][dir:received]',
        ),
        buildExpense(
          id: '4',
          amount: 500,
          category: 'Food',
          description: 'ignore',
        ),
      ];

      final net = calculateFriendSettlementNetByUid(expenses);
      expect(net['u1'], closeTo(-60, 0.0001));
      expect(net['u2'], closeTo(60, 0.0001));
      expect(net.containsKey('u3'), isFalse);
    });

    test('keeps settlement amounts separated by currency', () {
      final expenses = [
        buildExpense(
          id: '1',
          amount: 100,
          currency: 'USD',
          category: 'Settlement',
          description: 'A [uid:u1][dir:paid]',
        ),
        buildExpense(
          id: '2',
          amount: 40,
          currency: 'NOK',
          category: 'Settlement',
          description: 'B [uid:u1][dir:received]',
        ),
      ];

      final net = calculateFriendSettlementNetByUidAndCurrency(expenses);
      expect(net['u1']?['USD'], closeTo(-100, 0.0001));
      expect(net['u1']?['NOK'], closeTo(40, 0.0001));
    });
  });
}
