import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/data/models/freshness_snapshot.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/data/repositories/freshness_repository.dart';
import 'package:expense_tracker/features/friends/models/friend_contact.dart';
import 'package:expense_tracker/features/friends/models/friend_settlement.dart';
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
  final List<
    ({
      String friendUid,
      String direction,
      double amount,
      String currency,
      DateTime? date,
    })
  >
  recordedSettlements = [];
  List<FriendSettlement> settlements = const [];
  String? updatedSettlementId;
  DateTime? updatedSettlementDate;
  Map<String, Map<String, double>> balances = const {};
  int fetchFriendsCount = 0;

  @override
  Future<List<FriendContact>> fetchFriends() async {
    fetchFriendsCount += 1;
    return friends;
  }

  @override
  Future<FriendResolveResult> resolveFriend(String _) async {
    return const FriendResolveResult(exists: true, uid: 'new-friend');
  }

  @override
  Future<void> addFriend(String _) async {}

  @override
  Future<void> removeFriend(String _) async {}

  @override
  Future<Map<String, Map<String, double>>> fetchBalances() async => balances;

  @override
  Future<List<FriendSettlement>> fetchSettlements({
    String friendUid = '',
  }) async {
    return settlements
        .where(
          (settlement) =>
              friendUid.trim().isEmpty || settlement.uids.contains(friendUid),
        )
        .toList(growable: false);
  }

  @override
  Future<void> recordSettlement({
    required String friendUid,
    required String direction,
    required double amount,
    String currency = 'INR',
    DateTime? date,
  }) async {
    recordedSettlements.add((
      friendUid: friendUid,
      direction: direction,
      amount: amount,
      currency: currency,
      date: date,
    ));
    balances = {
      friendUid: {currency: amount},
    };
    final settlement = FriendSettlement(
      id: 'settlement-${settlements.length + 1}',
      uids: ['user-1', friendUid],
      payerUid: 'user-1',
      receiverUid: friendUid,
      amount: amount,
      currency: currency,
      date: date ?? DateTime(2026, 6, 7),
      createdAt: DateTime(2026, 6, 7),
    );
    settlements = [settlement, ...settlements];
  }

  @override
  Future<FriendSettlement> updateSettlementDate({
    required String settlementId,
    required DateTime date,
  }) async {
    updatedSettlementId = settlementId;
    updatedSettlementDate = date;
    final index = settlements.indexWhere(
      (settlement) => settlement.id == settlementId,
    );
    final existing = settlements[index];
    final updated = FriendSettlement(
      id: existing.id,
      uids: existing.uids,
      payerUid: existing.payerUid,
      receiverUid: existing.receiverUid,
      amount: existing.amount,
      currency: existing.currency,
      note: existing.note,
      createdBy: existing.createdBy,
      date: date,
      createdAt: existing.createdAt,
      updatedAt: date,
    );
    settlements = [
      ...settlements.take(index),
      updated,
      ...settlements.skip(index + 1),
    ];
    return updated;
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
  Future<void> createExpense(
    Expense expense, {
    List<Map<String, dynamic>> receiptItems = const [],
  }) async {
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

      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '120');
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();

      expect(friendsRepository.recordedSettlements, hasLength(1));
      final settlement = friendsRepository.recordedSettlements.single;
      expect(settlement.friendUid, 'friend-uid-1');
      expect(settlement.direction, 'paid');
      expect(settlement.amount, 120);
      expect(settlement.currency, 'INR');
      expect(settlement.date, isNotNull);
      expect(expenseRepository.created, isEmpty);
      expect(find.text('owes you'), findsOneWidget);
      expect(find.text('₹120.00'), findsWidgets);
      expect(find.text('Settlement history'), findsOneWidget);
      expect(find.text('You paid Test Friend'), findsOneWidget);
      expect(find.byTooltip('Change date'), findsOneWidget);

      await tester.tap(find.byTooltip('Change date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(friendsRepository.updatedSettlementId, 'settlement-1');
      expect(friendsRepository.updatedSettlementDate, isNotNull);
    },
  );

  testWidgets('auto-refresh skips friend reload when freshness is unchanged', (
    tester,
  ) async {
    final friendsRepository = _FakeFriendsRepository();
    final expenseRepository = _FakeExpenseRepository();
    final freshnessRepository = _FakeFreshnessRepository([
      _freshness(DateTime.parse('2026-06-07T10:00:00Z')),
      _freshness(DateTime.parse('2026-06-07T10:00:45Z')),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: FriendsPage(
            friendsRepository: friendsRepository,
            expenseRepository: expenseRepository,
            freshnessRepository: freshnessRepository,
            autoRefresh: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 45));
    await tester.pump();

    expect(friendsRepository.fetchFriendsCount, 1);
    expect(freshnessRepository.requests, hasLength(2));
    expect(freshnessRepository.requests.last.sections, ['friends']);
    expect(
      freshnessRepository.requests.last.since,
      DateTime.parse('2026-06-07T10:00:00Z'),
    );
  });
}

class _FakeFreshnessRepository extends FreshnessRepository {
  _FakeFreshnessRepository(this._responses)
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  final List<FreshnessSnapshot> _responses;
  final List<({DateTime? since, List<String> sections})> requests = [];

  @override
  Future<FreshnessSnapshot> fetchFreshness({
    DateTime? since,
    Iterable<String> sections = const [],
  }) async {
    requests.add((since: since, sections: sections.toList(growable: false)));
    final index = requests.length - 1;
    return _responses[index < _responses.length
        ? index
        : _responses.length - 1];
  }
}

FreshnessSnapshot _freshness(DateTime serverTime) {
  return FreshnessSnapshot(
    serverTime: serverTime,
    sections: const {'friends': FreshnessSection(changed: false)},
  );
}
