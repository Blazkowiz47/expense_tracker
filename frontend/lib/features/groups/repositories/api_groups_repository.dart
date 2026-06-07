import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_member.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiGroupsRepository {
  ApiGroupsRepository({
    required http.Client client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client,
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;
  static const String cacheBoxName = 'api_groups_cache_v1';
  static const String _groupsKey = 'groups';

  Box<String>? _cacheBox() {
    if (Hive.isBoxOpen(cacheBoxName)) {
      return Hive.box<String>(cacheBoxName);
    }
    return null;
  }

  Future<void> _saveListCache(
    String key,
    List<Map<String, dynamic>> items,
  ) async {
    final box = _cacheBox();
    if (box == null) return;
    await box.put(key, jsonEncode(items));
  }

  Future<List<Map<String, dynamic>>> _readListCache(String key) async {
    final box = _cacheBox();
    if (box == null) return const [];
    final raw = box.get(key);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<String> _scopedCacheKey(String key) async {
    final token = await _authTokenProvider.getBearerToken();
    return 'u:${_stableScopeHash(token)}:$key';
  }

  String _stableScopeHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _expensesKey(String groupId) => 'group:$groupId:expenses';
  String _membersKey(String groupId) => 'group:$groupId:members';

  Future<List<GroupSummary>> getCachedGroups() async {
    final cached = await _readListCache(await _scopedCacheKey(_groupsKey));
    return cached.map(GroupSummary.fromJson).toList(growable: false);
  }

  Future<List<GroupExpense>> getCachedExpenses(String groupId) async {
    final cached = await _readListCache(
      await _scopedCacheKey(_expensesKey(groupId)),
    );
    return cached.map(GroupExpense.fromJson).toList(growable: false);
  }

  Future<void> removeCachedExpenseIds(
    String groupId,
    Iterable<String> expenseIds,
  ) async {
    final ids = expenseIds.toSet();
    if (ids.isEmpty) return;
    final cacheKey = await _scopedCacheKey(_expensesKey(groupId));
    final cached = await _readListCache(cacheKey);
    if (cached.isEmpty) return;
    await _saveListCache(
      cacheKey,
      cached
          .where((item) => !ids.contains(item['id']?.toString() ?? ''))
          .toList(growable: false),
    );
  }

  Future<void> removeCachedGroupIds(Iterable<String> groupIds) async {
    final ids = groupIds.toSet();
    if (ids.isEmpty) return;
    final groupsCacheKey = await _scopedCacheKey(_groupsKey);
    final cachedGroups = await _readListCache(groupsCacheKey);
    await _saveListCache(
      groupsCacheKey,
      cachedGroups
          .where((item) => !ids.contains(item['id']?.toString() ?? ''))
          .toList(growable: false),
    );
    for (final groupId in ids) {
      await _saveListCache(await _scopedCacheKey(_expensesKey(groupId)), []);
      await _saveListCache(await _scopedCacheKey(_membersKey(groupId)), []);
    }
  }

  Future<void> upsertCachedExpenses(
    String groupId,
    Iterable<GroupExpense> expenses,
  ) async {
    final updates = expenses
        .where((expense) => expense.id.isNotEmpty)
        .toList(growable: false);
    if (updates.isEmpty) return;
    final cacheKey = await _scopedCacheKey(_expensesKey(groupId));
    final cachedById = <String, Map<String, dynamic>>{
      for (final item in await _readListCache(cacheKey))
        if ((item['id']?.toString() ?? '').isNotEmpty)
          item['id'].toString(): item,
    };
    for (final expense in updates) {
      cachedById[expense.id] = _expenseToCacheJson(expense);
    }
    await _saveListCache(cacheKey, cachedById.values.toList(growable: false));
  }

  Future<List<GroupMember>> getCachedMembers(String groupId) async {
    final cached = await _readListCache(
      await _scopedCacheKey(_membersKey(groupId)),
    );
    return cached.map(GroupMember.fromJson).toList(growable: false);
  }

  Future<List<GroupSummary>> fetchGroups() async {
    final response = await _request(method: 'GET', path: '/api/v1/groups');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawGroups = (payload['groups'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    final groups = rawGroups.map(GroupSummary.fromJson).toList(growable: false);
    await _saveListCache(
      await _scopedCacheKey(_groupsKey),
      rawGroups.toList(growable: false),
    );
    return groups;
  }

  Future<GroupSummary> createGroup({
    required String name,
    required GroupType groupType,
    List<String> members = const [],
    String ownerRole = '',
    Map<String, String> memberRolesByContact = const {},
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/api/v1/groups',
      body: <String, dynamic>{
        'name': name,
        'groupType': groupType.name,
        'members': members,
        if (ownerRole.trim().isNotEmpty) 'ownerRole': ownerRole.trim(),
        if (memberRolesByContact.isNotEmpty)
          'memberRolesByContact': memberRolesByContact,
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
    String role = '',
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/api/v1/groups/$groupId/members/add',
      body: <String, dynamic>{'emailOrPhone': emailOrPhone, 'role': role},
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return GroupSummary.fromJson(payload);
  }

  Future<GroupMember> updateMemberRole({
    required String groupId,
    required String memberUid,
    required String role,
  }) async {
    final response = await _request(
      method: 'PUT',
      path: '/api/v1/groups/$groupId/members/$memberUid/role',
      body: <String, dynamic>{'role': role},
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return GroupMember.fromJson(payload);
  }

  Future<List<GroupExpense>> fetchExpenses(String groupId) async {
    final response = await _request(
      method: 'GET',
      path: '/api/v1/groups/$groupId/expenses',
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawExpenses = (payload['expenses'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    final expenses = rawExpenses
        .map(GroupExpense.fromJson)
        .toList(growable: false);
    await _saveListCache(
      await _scopedCacheKey(_expensesKey(groupId)),
      rawExpenses.toList(growable: false),
    );
    return expenses;
  }

  Future<List<GroupMember>> fetchMembers(String groupId) async {
    final response = await _request(
      method: 'GET',
      path: '/api/v1/groups/$groupId/members',
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawMembers = (payload['members'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    final members = rawMembers
        .map(GroupMember.fromJson)
        .toList(growable: false);
    await _saveListCache(
      await _scopedCacheKey(_membersKey(groupId)),
      rawMembers.toList(growable: false),
    );
    return members;
  }

  Future<GroupExpense> addExpense({
    String? expenseId,
    required String groupId,
    required String description,
    required String paidBy,
    required String splitMode,
    required List<String> splitWith,
    required double amount,
    String currency = 'INR',
    List<String> targetCurrencies = const [],
    String category = '',
    List<String> attachments = const [],
    required DateTime date,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/api/v1/groups/$groupId/expenses',
      body: <String, dynamic>{
        'description': description,
        if ((expenseId ?? '').trim().isNotEmpty) 'id': expenseId!.trim(),
        'paidBy': paidBy,
        'splitMode': splitMode,
        'splitWith': splitWith,
        'amount': amount,
        'currency': currency,
        'targetCurrencies': targetCurrencies,
        'category': category,
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
    String currency = 'INR',
    List<String> targetCurrencies = const [],
    String category = '',
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
        'currency': currency,
        'targetCurrencies': targetCurrencies,
        'category': category,
        'attachments': attachments,
        'date': date.toUtc().toIso8601String(),
      },
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return GroupExpense.fromJson(payload);
  }

  Future<void> deleteExpense({
    required String groupId,
    required String expenseId,
  }) async {
    await _request(
      method: 'DELETE',
      path: '/api/v1/groups/$groupId/expenses/$expenseId',
    );
  }

  Future<String> uploadAttachment({
    required String groupId,
    required String expenseId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/groups/$groupId/attachments',
    );
    final mediaType = MediaType.parse(contentType);
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..fields['expenseId'] = expenseId
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
          contentType: mediaType,
        ),
      );
    final totalBytes = request.contentLength;
    final source = request.finalize();

    final streamedRequest = http.StreamedRequest('POST', uri)
      ..headers.addAll(request.headers)
      ..contentLength = totalBytes;

    var sentBytes = 0;
    source.listen(
      (chunk) {
        sentBytes += chunk.length;
        streamedRequest.sink.add(chunk);
        if (onProgress != null) {
          onProgress(sentBytes, totalBytes);
        }
      },
      onDone: () => streamedRequest.sink.close(),
      onError: streamedRequest.sink.addError,
      cancelOnError: true,
    );

    final streamed = await _client
        .send(streamedRequest)
        .timeout(const Duration(seconds: 30));
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

  Future<Uint8List> fetchAttachmentPreviewBytes({
    required String groupId,
    required String expenseId,
    required String attachmentUrl,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/groups/$groupId/expenses/$expenseId/attachments/preview',
    ).replace(queryParameters: {'url': attachmentUrl});
    final response = await _client.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/octet-stream',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        'GROUP_ATTACHMENT_PREVIEW: failed status=${response.statusCode} groupId=$groupId expenseId=$expenseId url=$attachmentUrl body=${response.body}',
      );
      throw Exception(
        'attachment preview request failed (${response.statusCode}): ${response.body}',
      );
    }
    return response.bodyBytes;
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
      'DELETE' => _client.delete(uri, headers: headers),
      _ => throw UnsupportedError('Unsupported method $method'),
    };

    final response = await request.timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Group request failed (${response.statusCode}): ${_errorMessage(response.body)}',
      );
    }
    return response;
  }

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = error['message']?.toString().trim();
          if (message != null && message.isNotEmpty) {
            return message;
          }
        }
      }
    } catch (_) {}
    return body;
  }

  Map<String, dynamic> _expenseToCacheJson(GroupExpense expense) {
    return <String, dynamic>{
      'id': expense.id,
      'groupId': expense.groupId,
      'createdBy': expense.createdBy,
      'updatedBy': expense.updatedBy,
      'paidBy': expense.paidBy,
      'splitMode': expense.splitMode,
      'splitWith': expense.splitWith,
      'amount': expense.amount,
      'currency': expense.currency,
      'convertedAmounts': expense.convertedAmounts,
      'category': expense.category,
      'description': expense.description,
      'attachments': expense.attachments,
      'date': expense.date.toUtc().toIso8601String(),
      'createdAt': expense.createdAt.toUtc().toIso8601String(),
      'updatedAt': expense.updatedAt.toUtc().toIso8601String(),
    };
  }
}
