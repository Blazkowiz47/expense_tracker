import 'dart:async';
import 'dart:convert';

import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/auth/repositories/auth_session_store.dart';
import 'package:http/http.dart' as http;

abstract class AuthRepository {
  Stream<AuthUser?> authStateChanges();
  Future<void> login({required String email, required String password});
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  });
  Future<void> signOut();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({
    http.Client? client,
    AuthSessionStore store = const AuthSessionStore(),
  }) : _client = client ?? http.Client(),
       _store = store {
    _bootstrap();
  }

  final http.Client _client;
  final AuthSessionStore _store;
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  Future<void> _bootstrap() async {
    final token = await _store.readToken();
    final cachedUser = await _store.readUser();
    if (token == null || token.isEmpty) {
      _controller.add(null);
      return;
    }
    try {
      final response = await _client.get(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/auth/me'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final user = _decodeUser(response.body);
        await _store.save(token: token, user: user);
        _controller.add(user);
        return;
      }
    } catch (_) {
      if (cachedUser != null) {
        _controller.add(cachedUser);
        return;
      }
    }
    await _store.clear();
    _controller.add(null);
  }

  @override
  Future<void> login({required String email, required String password}) {
    return _authenticate('/api/v1/auth/login', {
      'email': email,
      'password': password,
    });
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) {
    return _authenticate('/api/v1/auth/register', {
      'email': email,
      'password': password,
      'displayName': displayName,
    });
  }

  Future<void> _authenticate(String path, Map<String, dynamic> body) async {
    final response = await _client.post(
      Uri.parse('${ApiConfig.baseUrl}$path'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Authentication failed (${response.statusCode}): ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final token = decoded['token'] as String? ?? '';
    final user = AuthUser.fromJson(decoded['user'] as Map<String, dynamic>);
    if (token.isEmpty) {
      throw Exception('Authentication response did not include a token.');
    }
    await _store.save(token: token, user: user);
    _controller.add(user);
  }

  AuthUser _decodeUser(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return AuthUser.fromJson(decoded['user'] as Map<String, dynamic>);
  }

  @override
  Future<void> signOut() async {
    final token = await _store.readToken();
    if (token != null && token.isNotEmpty) {
      try {
        await _client.post(
          Uri.parse('${ApiConfig.baseUrl}/api/v1/auth/logout'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
      } catch (_) {}
    }
    await _store.clear();
    _controller.add(null);
  }
}
