import 'dart:async';

import 'package:expense_tracker/features/auth/cubit/auth_state.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  StreamSubscription<User?>? _subscription;

  Future<void> signInWithGoogle() async {
    emit(state.copyWith(status: AuthStatus.loading, message: null));
    try {
      await _repository.signInWithGoogle();
    } on FirebaseAuthException catch (error) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          message:
              'Google sign-in failed (${error.code}). ${error.message ?? ''}'
                  .trim(),
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          message: 'Google sign-in failed. Please try again. ($error)',
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

  void _onAuthChanged(User? user) {
    if (user == null) {
      emit(const AuthState(status: AuthStatus.unauthenticated));
      return;
    }
    debugPrint('AUTH: signed in uid=${user.uid} email=${user.email}');
    emit(AuthState(status: AuthStatus.authenticated, user: user));
    unawaited(_bootstrapUserDocument(user));
  }

  Future<void> _bootstrapUserDocument(User user) async {
    try {
      debugPrint('AUTH: bootstrapping Firestore user doc for uid=${user.uid}');
      await _userProfileRepository.ensureUserDocument(user);
      debugPrint(
        'AUTH: Firestore user doc upsert succeeded for uid=${user.uid}',
      );
    } on FirebaseException catch (error) {
      debugPrint(
        'AUTH: Firestore user doc upsert failed (${error.code}): ${error.message}',
      );
      emit(
        state.copyWith(
          message:
              'Profile bootstrap failed (${error.code}). ${error.message ?? ''}'
                  .trim(),
        ),
      );
    } catch (error) {
      debugPrint('AUTH: Firestore user doc upsert failed: $error');
      emit(state.copyWith(message: 'Profile bootstrap failed: $error'));
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
