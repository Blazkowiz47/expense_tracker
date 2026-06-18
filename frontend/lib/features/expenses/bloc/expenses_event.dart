part of 'expenses_bloc.dart';

sealed class ExpensesEvent extends Equatable {
  const ExpensesEvent();

  @override
  List<Object?> get props => [];
}

/// Load expenses from local storage
final class LoadExpenses extends ExpensesEvent {
  const LoadExpenses();
}

/// Refresh expenses from remote and sync
final class RefreshExpenses extends ExpensesEvent {
  const RefreshExpenses();
}

/// Create a new expense
final class CreateExpense extends ExpensesEvent {
  final Expense expense;
  final List<Map<String, dynamic>> receiptItems;
  final String billJobId;

  const CreateExpense({
    required this.expense,
    this.receiptItems = const [],
    this.billJobId = '',
  });

  @override
  List<Object?> get props => [expense, receiptItems, billJobId];
}

/// Update an existing expense
final class UpdateExpense extends ExpensesEvent {
  final Expense expense;
  final List<Map<String, dynamic>> receiptItems;
  final String billJobId;

  const UpdateExpense({
    required this.expense,
    this.receiptItems = const [],
    this.billJobId = '',
  });

  @override
  List<Object?> get props => [expense, receiptItems, billJobId];
}

/// Delete an expense (soft delete)
final class DeleteExpense extends ExpensesEvent {
  final String id;

  const DeleteExpense({required this.id});

  @override
  List<Object?> get props => [id];
}

/// Sync unsynced expenses to remote
final class SyncExpenses extends ExpensesEvent {
  const SyncExpenses();
}

/// Set date filter for expenses
final class SetDateFilter extends ExpensesEvent {
  final DateTime startDate;
  final DateTime endDate;

  const SetDateFilter({required this.startDate, required this.endDate});

  @override
  List<Object?> get props => [startDate, endDate];
}
