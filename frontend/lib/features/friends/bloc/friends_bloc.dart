import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/friend.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'friends_event.dart';
part 'friends_state.dart';

/// FriendsBloc listens to ExpensesBloc and derives unique friends from expense data
/// Friends are extracted from expense descriptions using simple text parsing
class FriendsBloc extends Bloc<FriendsEvent, FriendsState> {
  final ExpensesBloc _expensesBloc;
  late final StreamSubscription<ExpensesState> _expensesSubscription;

  FriendsBloc({required ExpensesBloc expensesBloc})
    : _expensesBloc = expensesBloc,
      super(const FriendsInitial()) {
    // Register event handlers
    on<LoadFriends>(_onLoadFriends);
    on<_UpdateFriendsFromExpenses>(_onUpdateFriendsFromExpenses);

    // Listen to ExpensesBloc stream and update friends automatically
    _expensesSubscription = _expensesBloc.stream.listen((expensesState) {
      if (expensesState is ExpensesLoaded) {
        add(_UpdateFriendsFromExpenses(expenses: expensesState.expenses));
      }
    });
  }

  /// Load friends from current expenses
  Future<void> _onLoadFriends(
    LoadFriends event,
    Emitter<FriendsState> emit,
  ) async {
    emit(const FriendsLoading());

    // Get current expenses from ExpensesBloc
    final expensesState = _expensesBloc.state;

    if (expensesState is! ExpensesLoaded) {
      emit(
        const FriendsError(
          message: 'Expenses not loaded. Cannot derive friends.',
        ),
      );
      return;
    }

    final friends = _extractFriendsFromExpenses(expensesState.expenses);
    emit(FriendsLoaded(friends: friends));
  }

  /// Update friends when expenses change (triggered by ExpensesBloc stream)
  Future<void> _onUpdateFriendsFromExpenses(
    _UpdateFriendsFromExpenses event,
    Emitter<FriendsState> emit,
  ) async {
    emit(const FriendsLoading());
    final friends = _extractFriendsFromExpenses(event.expenses);
    emit(FriendsLoaded(friends: friends));
  }

  /// Extract unique friends from a list of expenses
  /// Friends are identified by parsing expense descriptions for names
  List<Friend> _extractFriendsFromExpenses(List<Expense> expenses) {
    final Map<String, _FriendData> friendsMap = {};

    for (final expense in expenses) {
      // Skip deleted expenses
      if (expense.deleted) continue;

      // Extract friend names from description and title
      final names = _extractNamesFromText(
        '${expense.title} ${expense.description ?? ''}',
      );

      for (final name in names) {
        final normalizedName = _normalizeName(name);
        if (normalizedName.isEmpty) continue;

        if (!friendsMap.containsKey(normalizedName)) {
          friendsMap[normalizedName] = _FriendData(
            id: normalizedName.toLowerCase().replaceAll(' ', '_'),
            name: normalizedName,
          );
        }

        friendsMap[normalizedName]!.addExpense(expense.amount);
      }
    }

    // Convert to Friend objects and sort by expense count (descending)
    final friends =
        friendsMap.values
            .map(
              (data) => Friend(
                id: data.id,
                name: data.name,
                expenseCount: data.expenseCount,
                totalAmount: data.totalAmount,
              ),
            )
            .toList()
          ..sort((a, b) => b.expenseCount.compareTo(a.expenseCount));

    return friends;
  }

  /// Extract names from text by looking for common patterns like "with Name"
  Set<String> _extractNamesFromText(String text) {
    final names = <String>{};
    final lowerText = text.toLowerCase();

    // Pattern 1: "with Name" - extract single capitalized word after "with"
    final withPattern = RegExp(
      r'\bwith\s+([A-Z][a-z]+)\b',
      caseSensitive: false,
    );
    final withMatches = withPattern.allMatches(text);
    for (final match in withMatches) {
      final name = match.group(1);
      if (name != null) names.add(name);
    }

    // Pattern 2: Names after "and" in "with X and Y" context
    if (lowerText.contains('with') && lowerText.contains('and')) {
      final andPattern = RegExp(
        r'\band\s+([A-Z][a-z]+)\b',
        caseSensitive: false,
      );
      final andMatches = andPattern.allMatches(text);
      for (final match in andMatches) {
        final name = match.group(1);
        if (name != null) names.add(name);
      }
    }

    return names;
  }

  /// Normalize name by capitalizing first letter of each word
  String _normalizeName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';

    return trimmed
        .split(' ')
        .map((word) {
          if (word.isEmpty) return '';
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  @override
  Future<void> close() {
    _expensesSubscription.cancel();
    return super.close();
  }
}

/// Helper class to accumulate friend data while processing expenses
class _FriendData {
  final String id;
  final String name;
  int expenseCount = 0;
  double totalAmount = 0.0;

  _FriendData({required this.id, required this.name});

  void addExpense(double amount) {
    expenseCount++;
    totalAmount += amount;
  }
}
