import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class MockHttpClient extends Mock implements http.Client {}

class MockAuthTokenProvider extends Mock implements AuthTokenProvider {}

void main() {
  late MockHttpClient client;
  late MockAuthTokenProvider tokenProvider;
  late ExpenseRepository repository;

  setUpAll(() {
    registerFallbackValue(Uri.parse('http://localhost'));
  });

  setUp(() {
    client = MockHttpClient();
    tokenProvider = MockAuthTokenProvider();
    when(() => tokenProvider.getBearerToken()).thenAnswer((_) async => 'token');

    repository = ExpenseRepository(
      client: client,
      authTokenProvider: tokenProvider,
    );
  });

  tearDown(() {
    repository.dispose();
  });

  test('initialize loads expenses from backend', () async {
    when(() => client.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(
        jsonEncode({
          'expenses': [
            {
              'id': 'e1',
              'amount': 250.0,
              'category': 'Personal',
              'description': 'Groceries',
              'date': '2026-02-25T10:00:00Z',
              'updatedAt': '2026-02-25T10:00:00Z',
            },
          ],
        }),
        200,
      ),
    );

    await repository.initialize();

    final expenses = repository.getExpenses();
    expect(expenses, hasLength(1));
    expect(expenses.first.id, 'e1');
    expect(expenses.first.amount, 250.0);
  });

  test('createExpense sends POST to backend and updates cache', () async {
    final expense = Expense(
      core: ExpenseCore(
        id: 'local-id',
        title: 'Lunch',
        amount: 120,
        currency: 'INR',
        category: 'Personal',
        createdAt: DateTime(2026, 2, 25, 12, 30),
      ),
      description: 'Lunch',
      tags: const ['guilty pleasure', 'restaurant'],
    );

    when(
      () => client.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer(
      (_) async => http.Response(
        jsonEncode({
          'id': 'api-id',
          'amount': 120,
          'category': 'Personal',
          'description': 'Lunch',
          'tags': ['guilty pleasure', 'restaurant'],
          'date': '2026-02-25T12:30:00Z',
          'updatedAt': '2026-02-25T12:30:00Z',
        }),
        201,
      ),
    );

    await repository.createExpense(expense, billJobId: 'bill-job-1');

    expect(repository.getExpenseById('api-id'), isNotNull);
    expect(repository.getExpenseById('api-id')!.tags, [
      'guilty pleasure',
      'restaurant',
    ]);
    final body =
        verify(
              () => client.post(
                any(),
                headers: any(named: 'headers'),
                body: captureAny(named: 'body'),
              ),
            ).captured.single
            as String;
    final payload = jsonDecode(body) as Map<String, dynamic>;
    expect(payload['id'], 'local-id');
    expect(payload['amount'], 120);
    expect(payload['currency'], 'INR');
    expect(payload['category'], 'Personal');
    expect(payload['description'], 'Lunch');
    expect(payload.containsKey('paymentMethod'), isFalse);
    expect(payload['date'], '2026-02-25T12:30:00.000Z');
    expect(payload['tags'], ['guilty pleasure', 'restaurant']);
    expect(payload['billJobId'], 'bill-job-1');
  });

  test('refresh merges changed expenses and removes deleted ids', () async {
    var requestCount = 0;
    when(() => client.get(any(), headers: any(named: 'headers'))).thenAnswer((
      invocation,
    ) async {
      requestCount += 1;
      final uri = invocation.positionalArguments.first as Uri;
      if (requestCount == 1) {
        expect(uri.queryParameters.containsKey('updatedSince'), isFalse);
        return http.Response(
          jsonEncode({
            'serverTime': '2026-02-25T12:00:00Z',
            'expenses': [
              {
                'id': 'old',
                'amount': 100,
                'currency': 'NOK',
                'category': 'Food',
                'description': 'Old row',
                'date': '2026-02-24T10:00:00Z',
                'updatedAt': '2026-02-25T10:00:00Z',
              },
              {
                'id': 'deleted',
                'amount': 50,
                'currency': 'NOK',
                'category': 'Food',
                'description': 'Deleted row',
                'date': '2026-02-24T11:00:00Z',
                'updatedAt': '2026-02-25T10:30:00Z',
              },
            ],
          }),
          200,
        );
      }

      expect(uri.queryParameters['updatedSince'], '2026-02-25T12:00:00.000Z');
      return http.Response(
        jsonEncode({
          'serverTime': '2026-02-25T12:05:00Z',
          'deletedIds': ['deleted'],
          'expenses': [
            {
              'id': 'new',
              'amount': 200,
              'currency': 'NOK',
              'category': 'Travel',
              'description': 'New row',
              'date': '2026-02-25T12:01:00Z',
              'updatedAt': '2026-02-25T12:01:00Z',
            },
          ],
        }),
        200,
      );
    });

    await repository.initialize();
    await repository.refresh();

    expect(repository.getExpenseById('old'), isNotNull);
    expect(repository.getExpenseById('deleted'), isNull);
    expect(repository.getExpenseById('new')?.amount, 200);
  });

  test('updateExpense sends PUT and replaces cached expense', () async {
    when(
      () => client.put(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer(
      (_) async => http.Response(
        jsonEncode({
          'id': 'e1',
          'amount': 999,
          'category': 'Personal',
          'description': 'Updated',
          'date': '2026-02-25T12:30:00Z',
          'updatedAt': '2026-02-25T12:40:00Z',
        }),
        200,
      ),
    );

    final expense = Expense(
      core: ExpenseCore(
        id: 'e1',
        title: 'Updated',
        amount: 999,
        currency: 'NOK',
        category: 'Food',
        createdAt: DateTime(2026, 2, 25, 12, 30),
      ),
      description: 'Updated\nDinner notes',
      paymentMethod: 'card',
    );
    await repository.updateExpense(expense);

    expect(repository.getExpenseById('e1')?.amount, 999);
    final body =
        verify(
              () => client.put(
                any(),
                headers: any(named: 'headers'),
                body: captureAny(named: 'body'),
              ),
            ).captured.single
            as String;
    final payload = jsonDecode(body) as Map<String, dynamic>;
    expect(payload['amount'], 999);
    expect(payload['currency'], 'NOK');
    expect(payload['category'], 'Food');
    expect(payload['description'], 'Updated\nDinner notes');
    expect(payload['paymentMethod'], 'card');
    expect(payload['date'], '2026-02-25T12:30:00.000Z');
  });

  test('deleteExpense sends DELETE and removes local cache entry', () async {
    when(
      () => client.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer(
      (_) async => http.Response(
        jsonEncode({
          'id': 'e1',
          'amount': 100,
          'category': 'Personal',
          'description': 'Seed',
          'date': '2026-02-25T12:30:00Z',
          'updatedAt': '2026-02-25T12:30:00Z',
        }),
        201,
      ),
    );
    when(
      () => client.delete(any(), headers: any(named: 'headers')),
    ).thenAnswer((_) async => http.Response('', 204));

    await repository.createExpense(
      Expense(
        core: ExpenseCore(
          id: 'local',
          title: 'Seed',
          amount: 100,
          currency: 'INR',
          category: 'Personal',
          createdAt: DateTime(2026, 2, 25, 12, 30),
        ),
        description: 'Seed',
      ),
    );
    await repository.deleteExpense('e1');

    expect(repository.getExpenseById('e1'), isNull);
  });

  test('refresh throws when backend responds with non-200', () async {
    when(
      () => client.get(any(), headers: any(named: 'headers')),
    ).thenAnswer((_) async => http.Response('bad', 500));

    expect(repository.refresh, throwsException);
  });
}
