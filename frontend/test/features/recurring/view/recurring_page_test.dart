import 'package:expense_tracker/data/models/freshness_snapshot.dart';
import 'package:expense_tracker/data/repositories/freshness_repository.dart';
import 'package:expense_tracker/features/recurring/models/recurring_template.dart';
import 'package:expense_tracker/features/recurring/repositories/api_recurring_repository.dart';
import 'package:expense_tracker/features/recurring/view/recurring_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeRecurringRepository extends ApiRecurringRepository {
  _FakeRecurringRepository()
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  int fetchTemplateCount = 0;

  @override
  Future<List<RecurringTemplate>> fetchTemplates() async {
    fetchTemplateCount += 1;
    return const [];
  }

  @override
  Future<List<RecurringOccurrence>> fetchOccurrences({
    required String month,
  }) async {
    return [
      RecurringOccurrence(
        id: 'occ-rent',
        templateId: 'template-rent',
        period: month,
        kind: 'expense',
        title: 'Rent',
        category: 'Bills',
        currency: 'USD',
        expectedAmount: 12000,
        actualAmount: null,
        dueDate: DateTime.now(),
        actualDate: null,
        status: 'expected',
      ),
    ];
  }
}

void main() {
  testWidgets('opens confirm dialog for initial occurrence id', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecurringPage(
          repository: _FakeRecurringRepository(),
          initialOccurrenceId: 'occ-rent',
          openConfirmOnLaunch: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm actual'), findsOneWidget);
    expect(find.text('Rent'), findsWidgets);
    expect(find.text('Expected USD 12,000.00'), findsWidgets);
  });

  testWidgets('create dialog exposes currency and frequency controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: RecurringPage(repository: _FakeRecurringRepository())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add recurring'));
    await tester.pumpAndSettle();

    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('Frequency'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
  });

  testWidgets(
    'auto-refresh skips recurring reload when freshness is unchanged',
    (tester) async {
      final recurringRepository = _FakeRecurringRepository();
      final freshnessRepository = _FakeFreshnessRepository([
        _freshness(DateTime.parse('2026-06-07T10:00:00Z')),
        _freshness(DateTime.parse('2026-06-07T10:00:45Z')),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: RecurringPage(
            repository: recurringRepository,
            freshnessRepository: freshnessRepository,
            autoRefresh: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 45));
      await tester.pump();

      expect(recurringRepository.fetchTemplateCount, 1);
      expect(freshnessRepository.requests, hasLength(2));
      expect(freshnessRepository.requests.last.sections, ['recurring']);
      expect(
        freshnessRepository.requests.last.since,
        DateTime.parse('2026-06-07T10:00:00Z'),
      );
    },
  );
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
    sections: const {'recurring': FreshnessSection(changed: false)},
  );
}
