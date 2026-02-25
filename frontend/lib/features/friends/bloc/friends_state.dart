part of 'friends_bloc.dart';

sealed class FriendsState extends Equatable {
  const FriendsState();

  @override
  List<Object?> get props => [];
}

/// Initial state
final class FriendsInitial extends FriendsState {
  const FriendsInitial();
}

/// Loading friends from expenses
final class FriendsLoading extends FriendsState {
  const FriendsLoading();
}

/// Successfully loaded friends
final class FriendsLoaded extends FriendsState {
  final List<Friend> friends;

  const FriendsLoaded({required this.friends});

  @override
  List<Object?> get props => [friends];
}

/// Error loading friends
final class FriendsError extends FriendsState {
  final String message;

  const FriendsError({required this.message});

  @override
  List<Object?> get props => [message];
}
