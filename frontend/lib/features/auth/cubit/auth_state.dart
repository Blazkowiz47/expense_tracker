import 'package:equatable/equatable.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated, loading, failure }

class AuthState extends Equatable {
  const AuthState({this.status = AuthStatus.unknown, this.user, this.message});

  final AuthStatus status;
  final AuthUser? user;
  final String? message;

  AuthState copyWith({AuthStatus? status, AuthUser? user, String? message}) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      message: message,
    );
  }

  @override
  List<Object?> get props => [status, user, message];
}
