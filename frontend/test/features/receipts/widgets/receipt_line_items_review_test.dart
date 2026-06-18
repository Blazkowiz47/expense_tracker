import 'package:expense_tracker/features/expenses/repositories/bill_ai_repository.dart';
import 'package:expense_tracker/features/receipts/widgets/receipt_line_items_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('receipt item editor uses item tags and merged quantity unit', (
    tester,
  ) async {
    var items = const [
      BillLineItem(
        name: 'Soft Brownie',
        normalizedName: 'brownie',
        quantity: 1,
        unit: 'U',
        lineTotal: 52.6,
        tags: ['dessert'],
        confidence: 0.98,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ReceiptLineItemsReview(
              items: items,
              currency: 'NOK',
              onChanged: (updated) => setState(() => items = updated),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Compare as'), findsNothing);
    expect(find.text('Qty'), findsNothing);
    expect(find.text('Unit'), findsNothing);
    expect(find.text('Qty / unit'), findsOneWidget);
    expect(find.text('dessert'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('receipt-quantity-unit-0')),
      '1.5 kg',
    );
    await tester.pump();

    expect(items.first.quantity, 1.5);
    expect(items.first.unit, 'kg');

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add new tag...'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Guilty Pleasure');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(items.first.tags, ['dessert', 'guilty pleasure']);
    expect(find.text('guilty pleasure'), findsOneWidget);
  });
}
