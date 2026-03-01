import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

abstract class AuthRepository {
  Stream<User?> authStateChanges();
  Future<void> signInWithGoogle();
  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  @override
  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  @override
  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider();
    if (kIsWeb) {
      try {
        await _firebaseAuth.signInWithPopup(provider);
      } on FirebaseAuthException catch (error) {
        // Browsers may block popup flows; redirect is a safe fallback.
        if (error.code == 'popup-blocked' ||
            error.code == 'popup-closed-by-user') {
          await _firebaseAuth.signInWithRedirect(provider);
          return;
        }
        rethrow;
      }
      return;
    }

    await _firebaseAuth.signInWithProvider(provider);
  }

  @override
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }
}
