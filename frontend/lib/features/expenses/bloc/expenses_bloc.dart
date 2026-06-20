import 'package:equatable/equatable.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'expenses_event.dart';
part 'expenses_state.dart';

class ExpensesBloc extends Bloc<ExpensesEvent, ExpensesState> {
  final ExpenseRepository _repository;

  ExpensesBloc({required ExpenseRepository repository})
    : _repository = repository,
      super(const ExpensesInitial()) {
    // Register event handlers
    on<LoadExpenses>(_onLoadExpenses);
    on<RefreshExpenses>(_onRefreshExpenses);
    on<CreateExpense>(_onCreateExpense);
    on<UpdateExpense>(_onUpdateExpense);
    on<DeleteExpense>(_onDeleteExpense);
    on<SyncExpenses>(_onSyncExpenses);
    on<SetDateFilter>(_onSetDateFilter);
  }

  /// Load expenses from local storage
  Future<void> _onLoadExpenses(
    LoadExpenses event,
    Emitter<ExpensesState> emit,
  ) async {
    emit(const ExpensesLoading());
    try {
      await _repository.initialize();
      final expenses = _repository.getExpenses();
      emit(ExpensesLoaded(expenses: expenses));
    } catch (e) {
      emit(ExpensesError(message: e.toString()));
    }
  }

  /// Refresh expenses from remote and sync
  Future<void> _onRefreshExpenses(
    RefreshExpenses event,
    Emitter<ExpensesState> emit,
  ) async {
    emit(const ExpensesRefreshing());
    try {
      await _repository.refresh();
      final expenses = _repository.getExpenses();
      emit(ExpensesLoaded(expenses: expenses));
    } catch (e) {
      emit(ExpensesError(message: e.toString()));
    }
  }

  /// Create a new expense
  Future<void> _onCreateExpense(
    CreateExpense event,
    Emitter<ExpensesState> emit,
  ) async {
    _repository.upsertCachedExpenses([event.expense]);
    emit(ExpensesLoaded(expenses: _repository.getExpenses()));
    try {
      await _repository.createExpense(
        event.expense,
        receiptItems: event.receiptItems,
        billJobId: event.billJobId,
      );
      final expenses = _repository.getExpenses();
      emit(ExpensesLoaded(expenses: expenses));
    } catch (e) {
      _repository.removeCachedDeletedIds([event.expense.id]);
      emit(ExpensesError(message: e.toString()));
    }
  }

  /// Update an existing expense
  Future<void> _onUpdateExpense(
    UpdateExpense event,
    Emitter<ExpensesState> emit,
  ) async {
    final previous = _repository.getExpenseById(event.expense.id);
    _repository.upsertCachedExpenses([event.expense]);
    emit(ExpensesLoaded(expenses: _repository.getExpenses()));
    try {
      await _repository.updateExpense(
        event.expense,
        receiptItems: event.receiptItems,
        billJobId: event.billJobId,
      );
      final expenses = _repository.getExpenses();
      emit(ExpensesLoaded(expenses: expenses));
    } catch (e) {
      if (previous != null) {
        _repository.upsertCachedExpenses([previous]);
      }
      emit(ExpensesError(message: e.toString()));
    }
  }

  /// Delete an expense (soft delete)
  Future<void> _onDeleteExpense(
    DeleteExpense event,
    Emitter<ExpensesState> emit,
  ) async {
    try {
      await _repository.deleteExpense(event.id);
      final expenses = _repository.getExpenses();
      emit(ExpensesLoaded(expenses: expenses));
    } catch (e) {
      emit(ExpensesError(message: e.toString()));
    }
  }

  /// Sync unsynced expenses to remote
  Future<void> _onSyncExpenses(
    SyncExpenses event,
    Emitter<ExpensesState> emit,
  ) async {
    emit(const SyncInProgress());
    try {
      await _repository.syncExpenses();
      final expenses = _repository.getExpenses();
      emit(SyncSuccess(expenses: expenses));
    } catch (e) {
      emit(SyncError(message: e.toString()));
    }
  }

  /// Set date filter for expenses
  Future<void> _onSetDateFilter(
    SetDateFilter event,
    Emitter<ExpensesState> emit,
  ) async {
    try {
      final expenses = _repository.getExpensesByDateRange(
        event.startDate,
        event.endDate,
      );
      emit(ExpensesLoaded(expenses: expenses));
    } catch (e) {
      emit(ExpensesError(message: e.toString()));
    }
  }
}
