part of 'expenses_bloc.dart';

sealed class ExpensesState extends Equatable {
  const ExpensesState();

  @override
  List<Object?> get props => [];
}

/// Initial state
final class ExpensesInitial extends ExpensesState {
  const ExpensesInitial();
}

/// Loading expenses from storage
final class ExpensesLoading extends ExpensesState {
  const ExpensesLoading();
}

/// Successfully loaded expenses
final class ExpensesLoaded extends ExpensesState {
  final List<Expense> expenses;

  const ExpensesLoaded({required this.expenses});

  @override
  List<Object?> get props => [expenses];
}

/// Refreshing expenses from remote
final class ExpensesRefreshing extends ExpensesState {
  const ExpensesRefreshing();
}

/// Error loading expenses
final class ExpensesError extends ExpensesState {
  final String message;

  const ExpensesError({required this.message});

  @override
  List<Object?> get props => [message];
}

/// Syncing expenses to remote
final class SyncInProgress extends ExpensesState {
  const SyncInProgress();
}

/// Sync completed successfully
final class SyncSuccess extends ExpensesState {
  final List<Expense> expenses;

  const SyncSuccess({required this.expenses});

  @override
  List<Object?> get props => [expenses];
}

/// Sync failed with error
final class SyncError extends ExpensesState {
  final String message;

  const SyncError({required this.message});

  @override
  List<Object?> get props => [message];
}
