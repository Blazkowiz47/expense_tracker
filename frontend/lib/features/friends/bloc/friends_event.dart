part of 'friends_bloc.dart';

sealed class FriendsEvent extends Equatable {
  const FriendsEvent();

  @override
  List<Object?> get props => [];
}

/// Load friends from current expenses
final class LoadFriends extends FriendsEvent {
  const LoadFriends();
}

/// Internal event triggered when ExpensesBloc emits new state
final class _UpdateFriendsFromExpenses extends FriendsEvent {
  final List<Expense> expenses;

  const _UpdateFriendsFromExpenses({required this.expenses});

  @override
  List<Object?> get props => [expenses];
}
