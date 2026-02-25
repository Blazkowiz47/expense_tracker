import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';

// These tests verify that the Expense and ExpenseCore models can be
// correctly serialized to/from JSON, which is essential for Hive storage.
// The HiveExpensesDataSource uses these serialization methods to
// store and retrieve expenses from the Hive box.

void main() {
  late ExpenseCore testCore;
  late Expense testExpense;

  setUp(() {
    testCore = ExpenseCore(
      id: '1',
      title: 'Test Expense',
      amount: 50.0,
      currency: 'USD',
      category: 'Food',
      createdAt: DateTime(2024, 6, 15),
    );

    testExpense = Expense(
      core: testCore,
      description: 'Test description',
      paymentMethod: 'Cash',
      isSynced: false,
      deleted: false,
    );
  });

  group('Expense Serialization (for Hive Storage)', () {
    group('Expense.toJson and fromJson', () {
      test('should serialize all fields to JSON', () {
        final json = testExpense.toJson();

        expect(json['isSynced'], equals(false));
        expect(json['deleted'], equals(false));
        expect(json['description'], equals('Test description'));
        expect(json['paymentMethod'], equals('Cash'));
        expect(json['core'], isNotNull);
      });

      test('should deserialize from JSON correctly', () {
        final json = testExpense.toJson();
        final restored = Expense.fromJson(json);

        expect(restored.id, equals(testExpense.id));
        expect(restored.title, equals(testExpense.title));
        expect(restored.amount, equals(testExpense.amount));
        expect(restored.currency, equals(testExpense.currency));
        expect(restored.category, equals(testExpense.category));
        expect(restored.description, equals(testExpense.description));
        expect(restored.paymentMethod, equals(testExpense.paymentMethod));
        expect(restored.isSynced, equals(testExpense.isSynced));
        expect(restored.deleted, equals(testExpense.deleted));
      });

      test('should handle round-trip serialization', () {
        final json1 = testExpense.toJson();
        final restored1 = Expense.fromJson(json1);
        final json2 = restored1.toJson();
        final restored2 = Expense.fromJson(json2);

        expect(restored1.id, equals(restored2.id));
        expect(restored1.title, equals(restored2.title));
        expect(restored1.amount, equals(restored2.amount));
      });

      test('should serialize null optional fields as null', () {
        final minimal = Expense(
          core: testCore,
          description: null,
          updatedAt: null,
          paymentMethod: null,
          isSynced: false,
          deleted: false,
        );

        final json = minimal.toJson();
        final restored = Expense.fromJson(json);

        expect(restored.description, isNull);
        expect(restored.updatedAt, isNull);
        expect(restored.paymentMethod, isNull);
      });

      test('should preserve DateTime precision', () {
        final dateTime = DateTime(2024, 6, 15, 10, 30, 45, 123, 456);
        final withDateTime = testExpense.copyWith(
          core: testCore.copyWith(createdAt: dateTime),
          updatedAt: dateTime,
        );

        final json = withDateTime.toJson();
        final restored = Expense.fromJson(json);

        expect(restored.createdAt, equals(dateTime));
        expect(restored.updatedAt, equals(dateTime));
      });

      test('should handle special characters in strings', () {
        final special = testExpense.copyWith(
          description: 'Special chars: @#\$%^&*()',
          core: testCore.copyWith(
            title: 'Title with "quotes" and \'apostrophes\'',
          ),
        );

        final json = special.toJson();
        final restored = Expense.fromJson(json);

        expect(restored.description, equals('Special chars: @#\$%^&*()'));
        expect(
          restored.title,
          equals('Title with "quotes" and \'apostrophes\''),
        );
      });

      test('should preserve floating point precision', () {
        final precise = testExpense.copyWith(
          core: testCore.copyWith(amount: 99.99),
        );

        final json = precise.toJson();
        final restored = Expense.fromJson(json);

        expect(restored.amount, equals(99.99));
      });

      test('should handle boolean values correctly', () {
        final synced = testExpense.copyWith(isSynced: true, deleted: true);

        final json = synced.toJson();
        final restored = Expense.fromJson(json);

        expect(restored.isSynced, isTrue);
        expect(restored.deleted, isTrue);
      });
    });

    group('ExpenseCore serialization', () {
      test('should serialize all fields', () {
        final json = testCore.toJson();

        expect(json['id'], equals('1'));
        expect(json['title'], equals('Test Expense'));
        expect(json['amount'], equals(50.0));
        expect(json['currency'], equals('USD'));
        expect(json['category'], equals('Food'));
        expect(json['createdAt'], isNotNull);
      });

      test('should deserialize from JSON', () {
        final json = testCore.toJson();
        final restored = ExpenseCore.fromJson(json);

        expect(restored.id, equals(testCore.id));
        expect(restored.title, equals(testCore.title));
        expect(restored.amount, equals(testCore.amount));
        expect(restored.currency, equals(testCore.currency));
        expect(restored.category, equals(testCore.category));
        expect(restored.createdAt, equals(testCore.createdAt));
      });

      test('should handle null category', () {
        final noCat = ExpenseCore(
          id: '1',
          title: 'Test',
          amount: 50.0,
          currency: 'USD',
          category: null,
          createdAt: DateTime(2024, 6, 15),
        );
        final json = noCat.toJson();
        final restored = ExpenseCore.fromJson(json);

        expect(restored.category, isNull);
      });
    });

    group('Edge cases for Hive storage', () {
      test('should handle large amounts', () {
        final large = testExpense.copyWith(
          core: testCore.copyWith(amount: 999999999.99),
        );

        final json = large.toJson();
        final restored = Expense.fromJson(json);

        expect(restored.amount, equals(999999999.99));
      });

      test('should handle zero amount', () {
        final zero = testExpense.copyWith(core: testCore.copyWith(amount: 0.0));

        final json = zero.toJson();
        final restored = Expense.fromJson(json);

        expect(restored.amount, equals(0.0));
      });

      test('should handle negative amount', () {
        final negative = testExpense.copyWith(
          core: testCore.copyWith(amount: -50.0),
        );

        final json = negative.toJson();
        final restored = Expense.fromJson(json);

        expect(restored.amount, equals(-50.0));
      });

      test('should handle empty strings', () {
        final empty = testExpense.copyWith(description: '', paymentMethod: '');

        final json = empty.toJson();
        final restored = Expense.fromJson(json);

        expect(restored.description, equals(''));
        expect(restored.paymentMethod, equals(''));
      });

      test('should handle very long strings', () {
        final longText = 'x' * 10000;
        final long = testExpense.copyWith(description: longText);

        final json = long.toJson();
        final restored = Expense.fromJson(json);

        expect(restored.description, equals(longText));
      });

      test('should handle unicode characters', () {
        final unicode = testExpense.copyWith(
          description: 'Unicode: 你好 🎉 مرحبا',
        );

        final json = unicode.toJson();
        final restored = Expense.fromJson(json);

        expect(restored.description, equals('Unicode: 你好 🎉 مرحبا'));
      });
    });
  });

  group('Expense.copyWith', () {
    test('should create new instance with updated fields', () {
      final updated = testExpense.copyWith(
        description: 'Updated',
        isSynced: true,
      );

      expect(updated.description, equals('Updated'));
      expect(updated.isSynced, isTrue);
      expect(updated.deleted, equals(testExpense.deleted));
    });

    test('should preserve field values when using copyWith', () {
      // copyWith() method preserves old values when not specified
      // You need to explicitly provide null to set null values
      final withoutChanges = testExpense.copyWith();

      expect(withoutChanges.description, equals(testExpense.description));
      expect(withoutChanges.updatedAt, equals(testExpense.updatedAt));
    });
  });

  group('Expense getters', () {
    test('should provide convenient getters from core', () {
      expect(testExpense.id, equals('1'));
      expect(testExpense.title, equals('Test Expense'));
      expect(testExpense.amount, equals(50.0));
      expect(testExpense.currency, equals('USD'));
      expect(testExpense.category, equals('Food'));
      expect(testExpense.createdAt, equals(DateTime(2024, 6, 15)));
    });
  });
}
