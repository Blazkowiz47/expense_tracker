import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/features/auth/repositories/auth_session_store.dart';

abstract class AuthTokenProvider {
  Future<String> getBearerToken();
}

class SessionAuthTokenProvider implements AuthTokenProvider {
  const SessionAuthTokenProvider({
    AuthSessionStore store = const AuthSessionStore(),
  }) : _store = store;

  final AuthSessionStore _store;

  @override
  Future<String> getBearerToken() async {
    final mode = ApiConfig.authMode.toLowerCase();
    if (mode == 'dev') {
      return ApiConfig.devAuthToken;
    }

    String? token;
    try {
      token = await _store.readToken();
    } catch (_) {
      return ApiConfig.devAuthToken;
    }
    if (token != null && token.isNotEmpty) {
      return token;
    }
    return ApiConfig.devAuthToken;
  }
}
