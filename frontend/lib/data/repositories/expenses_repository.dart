import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/core/utils/backend_date_codec.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:http/http.dart' as http;

class ExpenseRepository {
  ExpenseRepository({http.Client? client, AuthTokenProvider? authTokenProvider})
    : _client = client ?? http.Client(),
      _authTokenProvider =
          authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;
  final Map<String, Expense> _expensesCache = {};
  static const _requestTimeout = Duration(seconds: 20);

  Future<void> initialize() => refresh();

  Future<void> refresh() async {
    final expenses = await _fetchExpenses();
    _expensesCache
      ..clear()
      ..addEntries(expenses.map((expense) => MapEntry(expense.id, expense)));
  }

  Future<void> createExpense(
    Expense expense, {
    List<Map<String, dynamic>> receiptItems = const [],
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/expenses');
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client
        .post(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(<String, dynamic>{
            'amount': expense.amount,
            'currency': expense.currency,
            'category': expense.category ?? 'Personal',
            'description': expense.description ?? expense.title,
            'paymentMethod': expense.paymentMethod ?? 'cash',
            'date': BackendDateCodec.encodeDate(expense.createdAt),
            if (expense.sourceType?.trim().isNotEmpty == true)
              'sourceType': expense.sourceType!.trim(),
            if (expense.sourceAccountId?.trim().isNotEmpty == true)
              'sourceAccountId': expense.sourceAccountId!.trim(),
            if (expense.sourceAccountName?.trim().isNotEmpty == true)
              'sourceAccountName': expense.sourceAccountName!.trim(),
            if (expense.sourcePaymentType?.trim().isNotEmpty == true)
              'sourcePaymentType': expense.sourcePaymentType!.trim(),
            if (expense.sourcePeriod?.trim().isNotEmpty == true)
              'sourcePeriod': expense.sourcePeriod!.trim(),
            if (expense.sourceSetupKey?.trim().isNotEmpty == true)
              'sourceSetupKey': expense.sourceSetupKey!.trim(),
            if (receiptItems.isNotEmpty) 'receiptItems': receiptItems,
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 201) {
      throw Exception(
        'create expense failed (${response.statusCode}): ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final created = Expense.fromBackendJson(payload);
    _expensesCache[created.id] = created;
  }

  Future<void> updateExpense(
    Expense expense, {
    List<Map<String, dynamic>> receiptItems = const [],
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/expenses/${expense.id}');
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client
        .put(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(<String, dynamic>{
            'amount': expense.amount,
            'currency': expense.currency,
            'category': expense.category ?? 'Personal',
            'description': expense.description ?? expense.title,
            'paymentMethod': expense.paymentMethod ?? 'cash',
            'date': BackendDateCodec.encodeDate(expense.createdAt),
            if (expense.sourceType?.trim().isNotEmpty == true)
              'sourceType': expense.sourceType!.trim(),
            if (expense.sourceAccountId?.trim().isNotEmpty == true)
              'sourceAccountId': expense.sourceAccountId!.trim(),
            if (expense.sourceAccountName?.trim().isNotEmpty == true)
              'sourceAccountName': expense.sourceAccountName!.trim(),
            if (expense.sourcePaymentType?.trim().isNotEmpty == true)
              'sourcePaymentType': expense.sourcePaymentType!.trim(),
            if (expense.sourcePeriod?.trim().isNotEmpty == true)
              'sourcePeriod': expense.sourcePeriod!.trim(),
            if (expense.sourceSetupKey?.trim().isNotEmpty == true)
              'sourceSetupKey': expense.sourceSetupKey!.trim(),
            if (receiptItems.isNotEmpty) 'receiptItems': receiptItems,
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'update expense failed (${response.statusCode}): ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final updated = Expense.fromBackendJson(payload);
    _expensesCache[updated.id] = updated;
  }

  Future<void> deleteExpense(String id) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/expenses/$id');
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client
        .delete(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'delete expense failed (${response.statusCode}): ${response.body}',
      );
    }

    _expensesCache.remove(id);
  }

  Future<String> exportExpensesCsv({
    String? category,
    DateTime? from,
    DateTime? to,
    String? query,
  }) async {
    final params = <String, String>{};
    if (category != null && category.trim().isNotEmpty) {
      params['category'] = category.trim();
    }
    if (from != null) {
      params['from'] = from.toUtc().toIso8601String();
    }
    if (to != null) {
      params['to'] = to.toUtc().toIso8601String();
    }
    if (query != null && query.trim().isNotEmpty) {
      params['q'] = query.trim();
    }
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/expenses-export.csv',
    ).replace(queryParameters: params.isEmpty ? null : params);
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client
        .get(
          uri,
          headers: <String, String>{
            'Accept': 'text/csv',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        'export csv failed (${response.statusCode}): ${response.body}',
      );
    }
    return response.body;
  }

  List<Expense> getExpenses() =>
      _expensesCache.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Expense? getExpenseById(String id) => _expensesCache[id];

  void removeCachedDeletedIds(Iterable<String> ids) {
    for (final id in ids) {
      _expensesCache.remove(id);
    }
  }

  void upsertCachedExpenses(Iterable<Expense> expenses) {
    for (final expense in expenses) {
      if (expense.id.isNotEmpty) {
        _expensesCache[expense.id] = expense;
      }
    }
  }

  List<Expense> getUnsyncedExpenses() => const [];

  List<Expense> getExpensesByDateRange(DateTime start, DateTime end) {
    return _expensesCache.values
        .where(
          (expense) =>
              !expense.createdAt.isBefore(start) &&
              !expense.createdAt.isAfter(end),
        )
        .toList(growable: false);
  }

  Future<void> syncExpenses() async {
    await refresh();
  }

  Future<List<Expense>> _fetchExpenses() async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/expenses?page=1&limit=200',
    );
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client
        .get(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'expenses request failed (${response.statusCode}): ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (payload['expenses'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return list.map(Expense.fromBackendJson).toList(growable: false);
  }

  void dispose() {
    _client.close();
  }
}
