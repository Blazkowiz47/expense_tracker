import 'dart:async';

import 'package:expense_tracker/features/accounts/models/financial_account.dart';
import 'package:expense_tracker/features/accounts/repositories/api_accounts_repository.dart';
import 'package:expense_tracker/features/credit_cards/models/credit_card.dart';
import 'package:expense_tracker/features/credit_cards/repositories/api_credit_cards_repository.dart';

class PaymentSourcesSnapshot {
  const PaymentSourcesSnapshot({
    required this.accounts,
    required this.creditCards,
    required this.fetchedAt,
  });

  final List<FinancialAccount> accounts;
  final List<CreditCardAccount> creditCards;
  final DateTime fetchedAt;

  bool get hasSources =>
      accounts.any((account) => !account.archived) ||
      creditCards.any((card) => !card.archived);
}

class PaymentSourcesLoadResult {
  const PaymentSourcesLoadResult({
    required this.snapshot,
    this.accountsError,
    this.creditCardsError,
  });

  final PaymentSourcesSnapshot snapshot;
  final Object? accountsError;
  final Object? creditCardsError;
}

class PaymentSourcesCache {
  PaymentSourcesCache._();

  static PaymentSourcesSnapshot? _snapshot;
  static Future<PaymentSourcesLoadResult>? _inflight;

  static PaymentSourcesSnapshot? get snapshot => _snapshot;

  static void clear() {
    _snapshot = null;
    _inflight = null;
  }

  static void prime({
    List<FinancialAccount>? accounts,
    List<CreditCardAccount>? creditCards,
  }) {
    final previous = _snapshot;
    _snapshot = PaymentSourcesSnapshot(
      accounts: List.unmodifiable(accounts ?? previous?.accounts ?? const []),
      creditCards: List.unmodifiable(
        creditCards ?? previous?.creditCards ?? const [],
      ),
      fetchedAt: DateTime.now(),
    );
  }

  static Future<PaymentSourcesLoadResult> load({
    required ApiAccountsRepository accountsRepository,
    required ApiCreditCardsRepository creditCardsRepository,
    Duration timeout = const Duration(seconds: 45),
    bool forceRefresh = false,
  }) {
    final running = _inflight;
    if (!forceRefresh && running != null) {
      return running;
    }
    final future = _load(
      accountsRepository: accountsRepository,
      creditCardsRepository: creditCardsRepository,
      timeout: timeout,
    );
    _inflight = future;
    return future.whenComplete(() {
      if (identical(_inflight, future)) {
        _inflight = null;
      }
    });
  }

  static Future<PaymentSourcesLoadResult> _load({
    required ApiAccountsRepository accountsRepository,
    required ApiCreditCardsRepository creditCardsRepository,
    required Duration timeout,
  }) async {
    List<FinancialAccount>? accounts;
    List<CreditCardAccount>? creditCards;
    Object? accountsError;
    Object? creditCardsError;

    await Future.wait<void>([
      accountsRepository
          .fetchAccounts()
          .timeout(timeout)
          .then<void>((value) => accounts = value)
          .catchError((Object error) {
            accountsError = error;
          }),
      creditCardsRepository
          .fetchCards()
          .timeout(timeout)
          .then<void>((value) => creditCards = value)
          .catchError((Object error) {
            creditCardsError = error;
          }),
    ]);

    final previous = _snapshot;
    final snapshot = PaymentSourcesSnapshot(
      accounts: List.unmodifiable(accounts ?? previous?.accounts ?? const []),
      creditCards: List.unmodifiable(
        creditCards ?? previous?.creditCards ?? const [],
      ),
      fetchedAt: DateTime.now(),
    );
    if (accounts != null || creditCards != null || previous == null) {
      _snapshot = snapshot;
    }

    return PaymentSourcesLoadResult(
      snapshot: snapshot,
      accountsError: accountsError,
      creditCardsError: creditCardsError,
    );
  }
}
