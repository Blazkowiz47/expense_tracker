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
  _FakeRecurringRepository({
    List<RecurringTemplate>? templates,
    List<RecurringOccurrence>? occurrences,
    this.failPause = false,
    this.failConfirm = false,
  }) : _templates = List<RecurringTemplate>.of(templates ?? const []),
       _occurrences = List<RecurringOccurrence>.of(
         occurrences ?? [_defaultOccurrence()],
       ),
       super(client: MockClient((_) async => http.Response('{}', 200)));

  final bool failPause;
  final bool failConfirm;
  var _templates = <RecurringTemplate>[];
  final List<RecurringOccurrence> _occurrences;
  int fetchTemplateCount = 0;
  String? confirmedOccurrenceId;
  _CreatedRecurring? createdTemplate;
  String? updatedTemplateId;
  String? pausedTemplateId;
  String? resumedTemplateId;
  String? deletedTemplateId;
  final requestedMonths = <String>[];

  @override
  Future<List<RecurringTemplate>> fetchTemplates() async {
    fetchTemplateCount += 1;
    return _templates;
  }

  @override
  Future<List<RecurringOccurrence>> fetchOccurrences({
    required String month,
  }) async {
    requestedMonths.add(month);
    return _occurrences
        .map(
          (item) => RecurringOccurrence(
            id: item.id,
            templateId: item.templateId,
            period: month,
            kind: item.kind,
            title: item.title,
            category: item.category,
            currency: item.currency,
            expectedAmount: item.expectedAmount,
            actualAmount: item.actualAmount,
            dueDate: item.dueDate,
            actualDate: item.actualDate,
            status: item.status,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<RecurringTemplate> createTemplate({
    required String title,
    required String kind,
    required double amount,
    required String category,
    required String currency,
    required String frequency,
    required int dayOfMonth,
    required DateTime startDate,
  }) async {
    createdTemplate = _CreatedRecurring(
      title: title,
      kind: kind,
      amount: amount,
      category: category,
      currency: currency,
      frequency: frequency,
      dayOfMonth: dayOfMonth,
    );
    final created = RecurringTemplate(
      id: 'template-created',
      title: title,
      kind: kind,
      amount: amount,
      currency: currency,
      category: category,
      frequency: frequency,
      dayOfMonth: dayOfMonth,
      startDate: startDate,
      nextDueDate: startDate,
      active: true,
    );
    _templates = [created, ..._templates];
    return created;
  }

  @override
  Future<RecurringTemplate> updateTemplate({
    required String id,
    required String title,
    required String kind,
    required double amount,
    required String category,
    required String currency,
    required String frequency,
    required int dayOfMonth,
    DateTime? startDate,
  }) async {
    updatedTemplateId = id;
    final updated = RecurringTemplate(
      id: id,
      title: title,
      kind: kind,
      amount: amount,
      currency: currency,
      category: category,
      frequency: frequency,
      dayOfMonth: dayOfMonth,
      startDate: startDate ?? DateTime.utc(2026),
      nextDueDate: DateTime.utc(2026, 6, dayOfMonth.clamp(1, 28)),
      active: true,
    );
    _templates = _templates
        .map((item) => item.id == id ? updated : item)
        .toList(growable: false);
    return updated;
  }

  @override
  Future<RecurringTemplate> pauseTemplate(String id) async {
    pausedTemplateId = id;
    if (failPause) {
      throw Exception('stale rule');
    }
    return _setActive(id, false);
  }

  @override
  Future<RecurringTemplate> resumeTemplate(String id) async {
    resumedTemplateId = id;
    return _setActive(id, true);
  }

  @override
  Future<void> deleteTemplate(String id) async {
    deletedTemplateId = id;
    _templates = _templates.where((item) => item.id != id).toList();
  }

  @override
  Future<RecurringOccurrence> confirmOccurrence({
    required String occurrenceId,
    required double actualAmount,
    required DateTime actualDate,
  }) async {
    confirmedOccurrenceId = occurrenceId;
    if (failConfirm) {
      throw Exception('stale occurrence');
    }
    final existing = _occurrences.firstWhere((item) => item.id == occurrenceId);
    return RecurringOccurrence(
      id: existing.id,
      templateId: existing.templateId,
      period: existing.period,
      kind: existing.kind,
      title: existing.title,
      category: existing.category,
      currency: existing.currency,
      expectedAmount: existing.expectedAmount,
      actualAmount: actualAmount,
      dueDate: existing.dueDate,
      actualDate: actualDate,
      status: 'confirmed',
    );
  }

  RecurringTemplate _setActive(String id, bool active) {
    final existing = _templates.firstWhere((item) => item.id == id);
    final updated = RecurringTemplate(
      id: existing.id,
      title: existing.title,
      kind: existing.kind,
      amount: existing.amount,
      currency: existing.currency,
      category: existing.category,
      frequency: existing.frequency,
      dayOfMonth: existing.dayOfMonth,
      startDate: existing.startDate,
      nextDueDate: existing.nextDueDate,
      active: active,
    );
    _templates = _templates
        .map((item) => item.id == id ? updated : item)
        .toList(growable: false);
    return updated;
  }
}

class _CreatedRecurring {
  const _CreatedRecurring({
    required this.title,
    required this.kind,
    required this.amount,
    required this.category,
    required this.currency,
    required this.frequency,
    required this.dayOfMonth,
  });

  final String title;
  final String kind;
  final double amount;
  final String category;
  final String currency;
  final String frequency;
  final int dayOfMonth;
}

RecurringOccurrence _defaultOccurrence() {
  return RecurringOccurrence(
    id: 'occ-rent',
    templateId: 'template-rent',
    period: '2026-06',
    kind: 'expense',
    title: 'Rent',
    category: 'Bills',
    currency: 'USD',
    expectedAmount: 12000,
    actualAmount: null,
    dueDate: DateTime.now(),
    actualDate: null,
    status: 'expected',
  );
}

RecurringTemplate _template({bool active = true}) {
  return RecurringTemplate(
    id: 'template-rent',
    title: 'Rent',
    kind: 'expense',
    amount: 12000,
    currency: 'USD',
    category: 'Bills',
    frequency: 'monthly',
    dayOfMonth: 5,
    startDate: DateTime.utc(2026, 6),
    nextDueDate: DateTime.utc(2026, 6, 5),
    active: active,
  );
}

void main() {
  testWidgets('opens confirm dialog for initial occurrence id', (tester) async {
    final repository = _FakeRecurringRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: RecurringPage(
          repository: repository,
          initialMonth: '2026-05',
          initialOccurrenceId: 'occ-rent',
          openConfirmOnLaunch: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm actual'), findsOneWidget);
    expect(find.text('Rent'), findsWidgets);
    expect(find.text('Expected USD 12,000.00'), findsWidgets);
    expect(repository.requestedMonths.first, '2026-05');
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
    expect(find.text('Insurance'), findsOneWidget);
  });

  testWidgets('insurance preset creates a yearly payment rule', (tester) async {
    final repository = _FakeRecurringRepository(occurrences: const []);
    await tester.pumpWidget(
      MaterialApp(home: RecurringPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add recurring'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insurance'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(
      tester.widget<TextField>(fields.at(0)).controller?.text,
      'Insurance premium',
    );
    expect(
      tester.widget<TextField>(fields.at(3)).controller?.text,
      'Insurance',
    );

    await tester.enterText(fields.at(1), '7200');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.createdTemplate?.title, 'Insurance premium');
    expect(repository.createdTemplate?.kind, 'expense');
    expect(repository.createdTemplate?.category, 'Insurance');
    expect(repository.createdTemplate?.frequency, 'yearly');
    expect(repository.createdTemplate?.amount, 7200);
    expect(find.text('Insurance premium'), findsOneWidget);
  });

  testWidgets('edits a saved recurring rule from the rules list', (
    tester,
  ) async {
    final repository = _FakeRecurringRepository(
      templates: [_template()],
      occurrences: const [],
    );

    await tester.pumpWidget(
      MaterialApp(home: RecurringPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Rule actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit recurring'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Apartment rent');
    await tester.enterText(find.byType(TextField).at(1), '13000');
    await tester.enterText(find.byType(TextField).at(2), '7');
    await tester.enterText(find.byType(TextField).at(3), 'Housing');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.updatedTemplateId, 'template-rent');
    expect(find.text('Apartment rent'), findsOneWidget);
    expect(find.text('USD 13,000.00'), findsOneWidget);
  });

  testWidgets('pauses resumes and deletes a saved recurring rule', (
    tester,
  ) async {
    final repository = _FakeRecurringRepository(
      templates: [_template()],
      occurrences: const [],
    );

    await tester.pumpWidget(
      MaterialApp(home: RecurringPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Rule actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(repository.pausedTemplateId, 'template-rent');
    expect(find.text('Paused'), findsOneWidget);

    await tester.tap(find.byTooltip('Rule actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();

    expect(repository.resumedTemplateId, 'template-rent');
    expect(find.text('Active'), findsOneWidget);

    await tester.tap(find.byTooltip('Rule actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.deletedTemplateId, 'template-rent');
    expect(find.text('No rules saved'), findsOneWidget);
  });

  testWidgets('shows an error and refreshes when pausing a stale rule fails', (
    tester,
  ) async {
    final repository = _FakeRecurringRepository(
      templates: [_template()],
      occurrences: const [],
      failPause: true,
    );

    await tester.pumpWidget(
      MaterialApp(home: RecurringPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Rule actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(repository.pausedTemplateId, 'template-rent');
    expect(repository.fetchTemplateCount, greaterThan(1));
    expect(
      find.text('Could not pause this recurring rule. Refreshed latest data.'),
      findsOneWidget,
    );
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets(
    'shows an error and refreshes when confirming stale occurrence fails',
    (tester) async {
      final repository = _FakeRecurringRepository(failConfirm: true);

      await tester.pumpWidget(
        MaterialApp(home: RecurringPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repository.confirmedOccurrenceId, 'occ-rent');
      expect(repository.fetchTemplateCount, greaterThan(1));
      expect(
        find.text(
          'Could not confirm this recurring item. Refreshed latest data.',
        ),
        findsOneWidget,
      );
      expect(find.text('Confirm'), findsOneWidget);
    },
  );

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
