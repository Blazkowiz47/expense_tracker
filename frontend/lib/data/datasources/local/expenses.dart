import 'package:hive/hive.dart';
import 'package:expense_tracker/data/datasources/expenses.dart';
import 'package:expense_tracker/data/models/expense.dart';

/// Hive-based implementation of ExpensesDatasource for offline storage
class ExpensesLocalDatasource implements ExpensesDatasource {
  static const String boxName = 'expenses';

  late final Box<dynamic> _box;

  /// Initialize Hive
  @override
  Future<void> initialize() async {
    try {
      _box = await Hive.openBox(boxName);
    } catch (e) {
      // If box is already open, just get it
      if (Hive.isBoxOpen(boxName)) {
        _box = Hive.box(boxName);
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<List<Expense>> getExpenses() async {
    try {
      final list = <Expense>[];
      for (var i = 0; i < _box.length; i++) {
        final value = _box.getAt(i);
        if (value is Map) {
          list.add(Expense.fromJson(Map<String, dynamic>.from(value)));
        }
      }
      return list;
    } catch (e) {
      throw Exception('Failed to get expenses from local storage: $e');
    }
  }

  @override
  Future<bool> createExpense(Expense expense) async {
    try {
      await _box.put(expense.id, expense.toJson());
      return true;
    } catch (e) {
      throw Exception('Failed to create expense locally: $e');
    }
  }

  @override
  Future<bool> updateExpense(Expense expense) async {
    try {
      if (_box.containsKey(expense.id)) {
        await _box.put(expense.id, expense.toJson());
        return true;
      }
      return false;
    } catch (e) {
      throw Exception('Failed to update expense locally: $e');
    }
  }

  @override
  Future<Expense?> getExpenseById(String id) async {
    try {
      final data = _box.get(id);
      if (data == null) return null;
      if (data is Map) {
        return Expense.fromJson(Map<String, dynamic>.from(data));
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get expense by id: $e');
    }
  }

  /// Close the Hive box (cleanup)
  @override
  Future<void> close() async {
    await _box.close();
  }
}
