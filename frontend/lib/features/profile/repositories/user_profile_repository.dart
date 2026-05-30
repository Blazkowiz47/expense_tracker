import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/auth/repositories/auth_session_store.dart';
import 'package:expense_tracker/features/profile/models/user_profile.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class UserProfileRepository {
  UserProfileRepository({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
    AuthSessionStore sessionStore = const AuthSessionStore(),
  }) : _client = client ?? http.Client(),
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider(),
       _sessionStore = sessionStore;

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;
  final AuthSessionStore _sessionStore;

  Future<void> ensureUserDocument(AuthUser user) async {
    await _sessionStore.saveUser(user);
  }

  Stream<UserProfile> watchProfile(AuthUser user) async* {
    yield await fetchProfile(fallback: user);
  }

  Future<UserProfile> fetchProfile({required AuthUser fallback}) async {
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client.get(
      Uri.parse('${ApiConfig.baseUrl}/api/v1/profile'),
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      return UserProfile(
        uid: fallback.uid,
        displayName: fallback.displayName,
        email: fallback.email,
        photoUrl: fallback.photoUrl,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return UserProfile(
      uid: (json['uid'] as String?) ?? fallback.uid,
      displayName: (json['displayName'] as String?) ?? fallback.displayName,
      email: (json['email'] as String?) ?? fallback.email,
      photoUrl: json['photoUrl'] as String?,
    );
  }

  Future<void> updateDisplayName({
    required AuthUser user,
    required String displayName,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client.put(
      Uri.parse('${ApiConfig.baseUrl}/api/v1/profile'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'displayName': displayName.trim()}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to save profile (${response.statusCode}): ${response.body}',
      );
    }
    await _sessionStore.saveUser(
      user.copyWith(displayName: displayName.trim()),
    );
  }

  Future<String> uploadProfilePhoto({
    required AuthUser user,
    required Uint8List bytes,
    String fileNameHint = 'profile_photo.jpg',
    void Function(double progress)? onProgress,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${ApiConfig.baseUrl}/api/v1/profile/photo'),
          )
          ..headers['Accept'] = 'application/json'
          ..headers['Authorization'] = 'Bearer $token'
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: fileNameHint,
              contentType: MediaType.parse(_contentType(fileNameHint)),
            ),
          );
    onProgress?.call(0.5);
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to upload photo (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final url = (payload['url'] as String?) ?? '';
    await _sessionStore.saveUser(user.copyWith(photoUrl: url));
    onProgress?.call(1);
    return '${ApiConfig.baseUrl}$url';
  }

  String _contentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
