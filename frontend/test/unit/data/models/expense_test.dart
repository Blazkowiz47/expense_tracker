import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';

void main() {
  group('Expense Data Model - Unit Tests', () {
    late ExpenseCore testCore;

    setUp(() {
      testCore = ExpenseCore(
        id: '1',
        title: 'Lunch at restaurant',
        amount: 50.0,
        currency: 'USD',
        category: 'Food',
        createdAt: DateTime.parse('2024-06-15T12:30:00Z'),
      );
    });

    test('should convert JSON to Expense object (fromJson)', () {
      final json = {
        'core': {
          'id': '1',
          'title': 'Lunch at restaurant',
          'amount': 50.0,
          'currency': 'USD',
          'category': 'Food',
          'createdAt': '2024-06-15T12:30:00Z',
        },
        'description': 'A nice meal with friends',
        'updatedAt': null,
        'paymentMethod': 'Cash',
        'isSynced': true,
        'deleted': false,
      };
      final expense = Expense.fromJson(json);
      expect(expense.id, '1');
      expect(expense.title, 'Lunch at restaurant');
      expect(expense.amount, 50.0);
      expect(expense.currency, 'USD');
      expect(expense.createdAt, DateTime.parse('2024-06-15T12:30:00Z'));
      expect(expense.description, 'A nice meal with friends');
      expect(expense.paymentMethod, 'Cash');
      expect(expense.isSynced, true);
      expect(expense.deleted, false);
    });

    test('should convert Expense object to JSON (toJson)', () {
      final expense = Expense(
        core: testCore,
        description: 'A nice meal with friends',
        updatedAt: null,
        paymentMethod: 'Cash',
        isSynced: false,
        deleted: false,
      );
      final json = expense.toJson();
      expect(json['core']['id'], '1');
      expect(json['core']['title'], 'Lunch at restaurant');
      expect(json['core']['amount'], 50.0);
      expect(json['core']['currency'], 'USD');
      expect(json['core']['category'], 'Food');
      expect(json['description'], 'A nice meal with friends');
      expect(json['paymentMethod'], 'Cash');
      expect(json['isSynced'], false);
      expect(json['deleted'], false);
    });

    test('should create a copy of Expense with modified fields (copyWith)', () {
      final expense = Expense(
        core: testCore,
        description: 'Original description',
        paymentMethod: 'Cash',
        isSynced: true,
        deleted: false,
      );
      final modifiedExpense = expense.copyWith(
        description: 'Updated description',
        isSynced: false,
      );
      expect(modifiedExpense.id, '1');
      expect(modifiedExpense.title, 'Lunch at restaurant');
      expect(modifiedExpense.amount, 50.0);
      expect(modifiedExpense.description, 'Updated description');
      expect(modifiedExpense.paymentMethod, 'Cash');
      expect(modifiedExpense.isSynced, false);
      expect(modifiedExpense.deleted, false);
    });

    test('should access core fields through convenience getters', () {
      final expense = Expense(core: testCore, isSynced: true, deleted: false);
      expect(expense.id, '1');
      expect(expense.title, 'Lunch at restaurant');
      expect(expense.amount, 50.0);
      expect(expense.currency, 'USD');
      expect(expense.category, 'Food');
      expect(expense.createdAt, DateTime.parse('2024-06-15T12:30:00Z'));
    });
  });
}
