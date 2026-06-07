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

  @override
  Future<List<RecurringTemplate>> fetchTemplates() async => const [];

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
        currency: 'INR',
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
    expect(find.text('Expected ₹12,000.00'), findsWidgets);
  });
}
