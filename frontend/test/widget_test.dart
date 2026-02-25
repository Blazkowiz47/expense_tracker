import 'package:expense_tracker/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots into shell with bottom navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExpenseTrackerApp());

    expect(find.text('Friends'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
