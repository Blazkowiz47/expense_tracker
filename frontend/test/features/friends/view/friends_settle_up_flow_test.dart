import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/features/friends/models/friend_contact.dart';
import 'package:expense_tracker/features/friends/repositories/api_friends_repository.dart';
import 'package:expense_tracker/features/friends/view/friends_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeAuthTokenProvider implements AuthTokenProvider {
  const _FakeAuthTokenProvider();

  @override
  Future<String> getBearerToken() async => 'test-token';
}

class _FakeFriendsRepository extends ApiFriendsRepository {
  _FakeFriendsRepository()
    : super(
        client: MockClient((_) async => http.Response('{}', 200)),
        authTokenProvider: const _FakeAuthTokenProvider(),
      );

  final List<FriendContact> friends = const [
    FriendContact(
      uid: 'friend-uid-1',
      displayName: 'Test Friend',
      email: 'friend@example.com',
      phone: '',
    ),
  ];
  final List<({String friendUid, String direction, double amount})>
  recordedSettlements = [];
  Map<String, double> balances = const {};

  @override
  Future<List<FriendContact>> fetchFriends() async => friends;

  @override
  Future<FriendResolveResult> resolveFriend(String _) async {
    return const FriendResolveResult(exists: true, uid: 'new-friend');
  }

  @override
  Future<void> addFriend(String _) async {}

  @override
  Future<void> removeFriend(String _) async {}

  @override
  Future<Map<String, double>> fetchBalances() async => balances;

  @override
  Future<void> recordSettlement({
    required String friendUid,
    required String direction,
    required double amount,
    String currency = 'INR',
  }) async {
    recordedSettlements.add((
      friendUid: friendUid,
      direction: direction,
      amount: amount,
    ));
    balances = {friendUid: amount};
  }
}

class _FakeExpenseRepository extends ExpenseRepository {
  _FakeExpenseRepository()
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  final List<Expense> _store = [];
  final List<Expense> created = [];

  @override
  Future<void> refresh() async {}

  @override
  List<Expense> getExpenses() => List<Expense>.from(_store);

  @override
  Future<void> createExpense(Expense expense) async {
    created.add(expense);
    _store.add(expense);
  }
}

void main() {
  testWidgets(
    'settle up records backend settlement visible in friend balance',
    (tester) async {
      final friendsRepository = _FakeFriendsRepository();
      final expenseRepository = _FakeExpenseRepository();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: Scaffold(
            body: FriendsPage(
              friendsRepository: friendsRepository,
              expenseRepository: expenseRepository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Friend'), findsOneWidget);

      await tester.tap(find.text('Test Friend'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '120');
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();

      expect(friendsRepository.recordedSettlements, hasLength(1));
      final settlement = friendsRepository.recordedSettlements.single;
      expect(settlement.friendUid, 'friend-uid-1');
      expect(settlement.direction, 'paid');
      expect(settlement.amount, 120);
      expect(expenseRepository.created, isEmpty);
      expect(find.text('owes you'), findsOneWidget);
    },
  );
}
