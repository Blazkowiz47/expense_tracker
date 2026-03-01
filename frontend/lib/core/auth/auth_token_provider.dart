import 'package:expense_tracker/core/config/api_config.dart';
import 'package:firebase_auth/firebase_auth.dart';

abstract class AuthTokenProvider {
  Future<String> getBearerToken();
}

class FirebaseAuthTokenProvider implements AuthTokenProvider {
  const FirebaseAuthTokenProvider({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth;

  final FirebaseAuth? _firebaseAuth;

  @override
  Future<String> getBearerToken() async {
    final mode = ApiConfig.authMode.toLowerCase();
    if (mode != 'firebase') {
      return ApiConfig.devAuthToken;
    }

    final auth = _firebaseAuth ?? FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user != null) {
      final idToken = await user.getIdToken();
      if (idToken != null && idToken.isNotEmpty) {
        return idToken;
      }
    }
    return ApiConfig.devAuthToken;
  }
}
