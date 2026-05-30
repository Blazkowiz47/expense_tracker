import 'dart:convert';

import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AuthSessionStore {
  static const boxName = 'auth_session_v1';
  static const _tokenKey = 'token';
  static const _userKey = 'user';

  const AuthSessionStore();

  static Future<void> ensureOpen() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<String>(boxName);
    }
  }

  Future<String?> readToken() async {
    if (!Hive.isBoxOpen(boxName)) return null;
    return Hive.box<String>(boxName).get(_tokenKey);
  }

  Future<AuthUser?> readUser() async {
    if (!Hive.isBoxOpen(boxName)) return null;
    final raw = Hive.box<String>(boxName).get(_userKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return AuthUser.fromJson(decoded);
  }

  Future<void> save({required String token, required AuthUser user}) async {
    await ensureOpen();
    await Hive.box<String>(boxName).put(_tokenKey, token);
    await Hive.box<String>(boxName).put(_userKey, jsonEncode(user.toJson()));
  }

  Future<void> saveUser(AuthUser user) async {
    await ensureOpen();
    await Hive.box<String>(boxName).put(_userKey, jsonEncode(user.toJson()));
  }

  Future<void> clear() async {
    await ensureOpen();
    await Hive.box<String>(boxName).delete(_tokenKey);
    await Hive.box<String>(boxName).delete(_userKey);
  }
}
