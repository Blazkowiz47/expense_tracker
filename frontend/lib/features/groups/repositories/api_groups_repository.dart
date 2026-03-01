import 'dart:convert';
import 'dart:typed_data';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_member.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiGroupsRepository {
  ApiGroupsRepository({
    required http.Client client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client,
       _authTokenProvider =
           authTokenProvider ?? const FirebaseAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;

  Future<List<GroupSummary>> fetchGroups() async {
    final response = await _request(method: 'GET', path: '/api/v1/groups');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawGroups = (payload['groups'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    return rawGroups.map(GroupSummary.fromJson).toList(growable: false);
  }

  Future<GroupSummary> createGroup({
    required String name,
    required GroupType groupType,
    List<String> members = const [],
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/api/v1/groups',
      body: <String, dynamic>{
        'name': name,
        'groupType': groupType.name,
        'members': members,
      },
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return GroupSummary.fromJson(payload);
  }

  Future<Map<String, dynamic>> leaveGroup(String groupId) async {
    final response = await _request(
      method: 'POST',
      path: '/api/v1/groups/$groupId/leave',
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<GroupSummary> addMember({
    required String groupId,
    required String emailOrPhone,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/api/v1/groups/$groupId/members/add',
      body: <String, dynamic>{'emailOrPhone': emailOrPhone},
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return GroupSummary.fromJson(payload);
  }

  Future<List<GroupExpense>> fetchExpenses(String groupId) async {
    final response = await _request(
      method: 'GET',
      path: '/api/v1/groups/$groupId/expenses',
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawExpenses = (payload['expenses'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    return rawExpenses.map(GroupExpense.fromJson).toList(growable: false);
  }

  Future<List<GroupMember>> fetchMembers(String groupId) async {
    final response = await _request(
      method: 'GET',
      path: '/api/v1/groups/$groupId/members',
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawMembers = (payload['members'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    return rawMembers.map(GroupMember.fromJson).toList(growable: false);
  }

  Future<GroupExpense> addExpense({
    required String groupId,
    required String description,
    required String paidBy,
    required String splitMode,
    required List<String> splitWith,
    required double amount,
    List<String> attachments = const [],
    required DateTime date,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/api/v1/groups/$groupId/expenses',
      body: <String, dynamic>{
        'description': description,
        'paidBy': paidBy,
        'splitMode': splitMode,
        'splitWith': splitWith,
        'amount': amount,
        'attachments': attachments,
        'date': date.toUtc().toIso8601String(),
      },
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return GroupExpense.fromJson(payload);
  }

  Future<GroupExpense> updateExpense({
    required String groupId,
    required String expenseId,
    required String description,
    required String paidBy,
    required String splitMode,
    required List<String> splitWith,
    required double amount,
    List<String> attachments = const [],
    required DateTime date,
  }) async {
    final response = await _request(
      method: 'PUT',
      path: '/api/v1/groups/$groupId/expenses/$expenseId',
      body: <String, dynamic>{
        'description': description,
        'paidBy': paidBy,
        'splitMode': splitMode,
        'splitWith': splitWith,
        'amount': amount,
        'attachments': attachments,
        'date': date.toUtc().toIso8601String(),
      },
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return GroupExpense.fromJson(payload);
  }

  Future<String> uploadAttachment({
    required String groupId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/groups/$groupId/attachments',
    );
    final mediaType = MediaType.parse(contentType);
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
          contentType: mediaType,
        ),
      );
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'attachment upload failed (${response.statusCode}): ${response.body}',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final url = (payload['url'] as String?) ?? '';
    if (url.isEmpty) {
      throw Exception('attachment upload returned empty url');
    }
    return url;
  }

  Future<http.Response> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    final request = switch (method) {
      'GET' => _client.get(uri, headers: headers),
      'POST' => _client.post(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      ),
      'PUT' => _client.put(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      ),
      _ => throw UnsupportedError('Unsupported method $method'),
    };

    final response = await request.timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'group request failed (${response.statusCode}): ${response.body}',
      );
    }
    return response;
  }
}
