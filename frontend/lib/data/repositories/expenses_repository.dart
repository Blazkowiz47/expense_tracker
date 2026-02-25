import 'dart:developer';

import 'package:expense_tracker/data/datasources/local/expenses.dart';
import 'package:expense_tracker/data/datasources/remote/expenses.dart';
import 'package:expense_tracker/data/models/expense.dart';

class ExpenseRepository {
  final ExpensesRemoteDatasource _remoteDataSource;
  final ExpensesLocalDatasource _localDataSource;

  // In-memory cache for fast access
  final Map<String, Expense> _expensesCache = {};
  bool _isInitialized = false;

  ExpenseRepository({
    required ExpensesRemoteDatasource remoteDataSource,
    required ExpensesLocalDatasource localDataSource,
  }) : _remoteDataSource = remoteDataSource,
       _localDataSource = localDataSource;

  /// Initialize the repository by loading all expenses from local storage
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final expenses = await _localDataSource.getExpenses();
      _expensesCache.clear();
      for (final expense in expenses) {
        _expensesCache[expense.id] = expense;
      }
      _isInitialized = true;
      log(
        'ExpenseRepository initialized with ${_expensesCache.length} expenses',
      );
    } catch (e) {
      log('Error initializing ExpenseRepository: $e', level: 3);
      rethrow;
    }
  }

  /// Create a new expense locally (marked as unsynced)
  Future<void> createExpense(Expense expense) async {
    try {
      // Always save locally with isSynced: false
      final unsyncedExpense = expense.copyWith(isSynced: false);
      final success = await _localDataSource.createExpense(unsyncedExpense);
      if (!success) throw Exception('Failed to create expense locally');

      // Update cache
      _expensesCache[expense.id] = unsyncedExpense;
      log('Created expense ${expense.id} locally (unsynced)');
    } catch (e) {
      log('Error creating expense: $e', level: 3);
      rethrow;
    }
  }

  /// Update an expense locally (marked as unsynced)
  Future<void> updateExpense(Expense expense) async {
    try {
      // Always save locally with isSynced: false
      final unsyncedExpense = expense.copyWith(isSynced: false);
      final success = await _localDataSource.updateExpense(unsyncedExpense);
      if (!success) throw Exception('Failed to update expense locally');

      // Update cache
      _expensesCache[expense.id] = unsyncedExpense;
      log('Updated expense ${expense.id} locally (unsynced)');
    } catch (e) {
      log('Error updating expense: $e', level: 3);
      rethrow;
    }
  }

  /// Get expense by ID from cache
  Expense? getExpenseById(String id) {
    return _expensesCache[id];
  }

  /// Get all expenses from cache
  List<Expense> getExpenses() {
    return _expensesCache.values.toList();
  }

  /// Get unsynced expenses from cache
  List<Expense> getUnsyncedExpenses() {
    return _expensesCache.values.where((expense) => !expense.isSynced).toList();
  }

  /// Get expenses by date range from cache
  List<Expense> getExpensesByDateRange(DateTime start, DateTime end) {
    return _expensesCache.values
        .where(
          (expense) =>
              expense.createdAt.isAfter(start) &&
              expense.createdAt.isBefore(end),
        )
        .toList();
  }

  /// Sync all unsynced expenses to remote
  Future<void> syncExpenses() async {
    try {
      final unsyncedExpenses = getUnsyncedExpenses();
      log('Starting sync for ${unsyncedExpenses.length} expenses');

      if (unsyncedExpenses.isEmpty) {
        log('No expenses to sync');
        return;
      }

      // Iterate a copy so we don't run into accidental modification issues
      for (final expense in List<Expense>.from(unsyncedExpenses)) {
        await _syncExpenseToRemote(expense);
      }

      log('Completed syncing ${unsyncedExpenses.length} expenses');
    } catch (e) {
      log('Error syncing expenses: $e', level: 3);
      rethrow;
    }
  }

  /// Refresh all expenses from remote and sync local changes
  Future<void> refresh() async {
    try {
      log('Starting refresh from remote');

      // First, sync all local unsynced changes to remote
      await syncExpenses();

      // Then, pull latest from remote
      final remoteExpenses = await _remoteDataSource.getExpenses();
      // Persist remote results to local storage (upsert-like behavior)
      _expensesCache.clear();
      for (final expense in remoteExpenses) {
        // Try update; if update fails (not found), create
        final updated = await _localDataSource.updateExpense(expense);
        if (!updated) {
          await _localDataSource.createExpense(expense);
        }

        // Mark remote records as synced locally
        final syncedRemote = expense.copyWith(isSynced: true);
        _expensesCache[syncedRemote.id] = syncedRemote;
      }

      log(
        'Refreshed ${_expensesCache.length} expenses from remote and persisted locally',
      );
    } catch (e) {
      log('Error refreshing expenses: $e', level: 3);
      rethrow;
    }
  }

  /// Sync a single expense to remote
  Future<void> _syncExpenseToRemote(Expense expense) async {
    try {
      bool synced = false;

      if (expense.deleted) {
        // Soft-deleted locally -> we don't have a remote delete method anymore.
        // Instead, we update the remote record to mark it as deleted too.
        synced = await _remoteDataSource.updateExpense(expense);
      } else {
        // For new or updated expenses, try update first. If remote says it
        // doesn't exist (update returns false), try create.
        synced = await _remoteDataSource.updateExpense(expense);
        if (!synced) {
          synced = await _remoteDataSource.createExpense(expense);
        }
      }

      if (synced) {
        // Mark as synced in both local and cache
        final syncedExpense = expense.copyWith(isSynced: true);
        await _localDataSource.updateExpense(syncedExpense);
        _expensesCache[expense.id] = syncedExpense;
        log('Successfully synced expense ${expense.id}');
      } else {
        log('Failed to sync expense ${expense.id}', level: 2);
      }
    } catch (e) {
      log('Error syncing expense ${expense.id} to remote: $e', level: 3);
    }
  }
}
