import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppLineChart renders labeled trend points', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppLineChart(
            points: [
              AppChartPoint(label: 'M', value: 120),
              AppChartPoint(label: 'T', value: 240),
              AppChartPoint(label: 'W', value: 80),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(AppLineChart), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppLineChart),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });

  testWidgets('AppSegmentedBar renders positive segments', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppSegmentedBar(
            segments: [
              AppChartSegment(value: 30, color: Colors.green, label: 'Food'),
              AppChartSegment(value: 70, color: Colors.blue, label: 'Rent'),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(AppSegmentedBar), findsOneWidget);
    expect(find.byType(Expanded), findsNWidgets(2));
  });
}
