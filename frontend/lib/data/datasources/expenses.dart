import 'package:expense_tracker/data/models/expense.dart';

abstract class ExpensesDatasource {
  /// Initialize the datasource
  Future<void> initialize();

  /// Close/cleanup the datasource
  Future<void> close();

  Future<bool> createExpense(Expense expense);
  Future<bool> updateExpense(Expense expense);
  Future<Expense?> getExpenseById(String id);
  Future<List<Expense>> getExpenses();
}
