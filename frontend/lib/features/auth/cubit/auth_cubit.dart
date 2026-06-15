import 'dart:async';

import 'package:expense_tracker/features/auth/cubit/auth_state.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit({
    required AuthRepository repository,
    required UserProfileRepository userProfileRepository,
  }) : _repository = repository,
       _userProfileRepository = userProfileRepository,
       super(const AuthState()) {
    _subscription = _repository.authStateChanges().listen(_onAuthChanged);
  }

  final AuthRepository _repository;
  final UserProfileRepository _userProfileRepository;
  StreamSubscription<AuthUser?>? _subscription;

  Future<void> login({required String email, required String password}) async {
    emit(state.copyWith(status: AuthStatus.loading, message: null));
    try {
      await _repository.login(email: email, password: password);
    } catch (error) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          message: 'Sign in failed. Please try again. ($error)',
        ),
      );
    }
  }

  Future<void> loginWithGoogle() async {
    emit(state.copyWith(status: AuthStatus.loading, message: null));
    try {
      await _repository.loginWithGoogle();
    } catch (error) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          message: 'Google sign in failed. Please try again. ($error)',
        ),
      );
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    emit(state.copyWith(status: AuthStatus.loading, message: null));
    try {
      await _repository.register(
        email: email,
        password: password,
        displayName: displayName,
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          message: 'Registration failed. Please try again. ($error)',
        ),
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _repository.signOut();
    } catch (_) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          message: 'Sign out failed. Please try again.',
        ),
      );
    }
  }

  void _onAuthChanged(AuthUser? user) {
    if (user == null) {
      emit(const AuthState(status: AuthStatus.unauthenticated));
      return;
    }
    debugPrint('AUTH: signed in uid=${user.uid} email=${user.email}');
    emit(AuthState(status: AuthStatus.authenticated, user: user));
    unawaited(_userProfileRepository.ensureUserDocument(user));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
