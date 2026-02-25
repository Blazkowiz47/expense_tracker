import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:http/http.dart' as http;

class ExpenseRepository {
  ExpenseRepository({http.Client? client, AuthTokenProvider? authTokenProvider})
    : _client = client ?? http.Client(),
      _authTokenProvider =
          authTokenProvider ?? const FirebaseAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;
  final Map<String, Expense> _expensesCache = {};

  Future<void> initialize() => refresh();

  Future<void> refresh() async {
    final expenses = await _fetchExpenses();
    _expensesCache
      ..clear()
      ..addEntries(expenses.map((expense) => MapEntry(expense.id, expense)));
  }

  Future<void> createExpense(Expense expense) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/expenses');
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(<String, dynamic>{
        'amount': expense.amount,
        'category': expense.category ?? 'Personal',
        'description': expense.description ?? expense.title,
        'date': expense.createdAt.toUtc().toIso8601String(),
      }),
    );

    if (response.statusCode != 201) {
      throw Exception(
        'create expense failed (${response.statusCode}): ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final created = _fromBackend(payload);
    _expensesCache[created.id] = created;
  }

  Future<void> updateExpense(Expense expense) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/expenses/${expense.id}');
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client.put(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(<String, dynamic>{
        'amount': expense.amount,
        'category': expense.category ?? 'Personal',
        'description': expense.description ?? expense.title,
        'date': expense.createdAt.toUtc().toIso8601String(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'update expense failed (${response.statusCode}): ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final updated = _fromBackend(payload);
    _expensesCache[updated.id] = updated;
  }

  Future<void> deleteExpense(String id) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/expenses/$id');
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client.delete(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'delete expense failed (${response.statusCode}): ${response.body}',
      );
    }

    _expensesCache.remove(id);
  }

  List<Expense> getExpenses() =>
      _expensesCache.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Expense? getExpenseById(String id) => _expensesCache[id];

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
    final response = await _client.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'expenses request failed (${response.statusCode}): ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (payload['expenses'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return list.map(_fromBackend).toList(growable: false);
  }

  Expense _fromBackend(Map<String, dynamic> json) {
    final description = (json['description'] as String?)?.trim();
    final category = (json['category'] as String?)?.trim();
    final dateRaw = (json['date'] as String?) ?? '';
    final createdAt = DateTime.tryParse(dateRaw)?.toLocal() ?? DateTime.now();
    final updatedRaw = json['updatedAt'] as String?;

    return Expense(
      core: ExpenseCore(
        id: (json['id'] as String?) ?? '',
        title: (description != null && description.isNotEmpty)
            ? description
            : (category != null && category.isNotEmpty ? category : 'Expense'),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: 'INR',
        category: category,
        createdAt: createdAt,
      ),
      description: description,
      updatedAt: updatedRaw != null ? DateTime.tryParse(updatedRaw) : null,
      paymentMethod: null,
      isSynced: true,
      deleted: false,
    );
  }

  void dispose() {
    _client.close();
  }
}
