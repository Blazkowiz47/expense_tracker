import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:expense_tracker/features/planning/view/monthly_planning_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeMonthlyPlanRepository extends MonthlyPlanRepository {
  _FakeMonthlyPlanRepository()
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  Map<String, double>? savedBudgets;
  String? savedCurrency;
  int fetchCount = 0;

  @override
  Future<MonthlyPlan> fetchPlan({required String month}) async {
    fetchCount += 1;
    final actual = fetchCount == 1 ? 1500.0 : 1750.0;
    return MonthlyPlan(
      month: '2026-06',
      currency: 'INR',
      totalBudget: 5000,
      totalActual: actual,
      totalRemaining: 5000 - actual,
      categories: [
        MonthlyPlanCategory(
          category: 'Groceries',
          budget: 5000,
          actual: actual,
          remaining: 5000 - actual,
          progress: actual / 5000,
          overBudget: false,
        ),
        const MonthlyPlanCategory(
          category: 'Pet care',
          budget: 0,
          actual: 250,
          remaining: -250,
          progress: 0,
          overBudget: false,
        ),
      ],
    );
  }

  @override
  Future<MonthlyPlan> savePlan({
    required String month,
    required String currency,
    required Map<String, double> budgets,
  }) async {
    savedBudgets = budgets;
    savedCurrency = currency;
    final totalBudget = budgets.values.fold<double>(
      0,
      (total, value) => total + value,
    );
    return MonthlyPlan(
      month: month,
      currency: currency,
      totalBudget: totalBudget,
      totalActual: 1500,
      totalRemaining: totalBudget - 1500,
      categories: budgets.entries
          .map((entry) {
            final actual = entry.key == 'Groceries' ? 1250.0 : 0.0;
            return MonthlyPlanCategory(
              category: entry.key,
              budget: entry.value,
              actual: actual,
              remaining: entry.value - actual,
              progress: entry.value <= 0 ? 0 : actual / entry.value,
              overBudget: false,
            );
          })
          .toList(growable: false),
    );
  }
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

void main() {
  testWidgets('budget editor keeps household and actual categories', (
    tester,
  ) async {
    final repository = _FakeMonthlyPlanRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MonthlyPlanningCard(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit monthly plan'));
    await tester.pumpAndSettle();

    expect(_textFieldWithLabel('Rent and housing'), findsOneWidget);
    expect(_textFieldWithLabel('Pet care'), findsOneWidget);

    await tester.tap(find.text('INR').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(_textFieldWithLabel('Add category'));
    await tester.pumpAndSettle();
    await tester.enterText(_textFieldWithLabel('Add category'), 'Car');
    await tester.ensureVisible(find.byTooltip('Add category'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add category'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_textFieldWithLabel('Car'));
    await tester.pumpAndSettle();
    await tester.enterText(_textFieldWithLabel('Car'), '2500');
    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();

    expect(repository.savedBudgets?['Groceries'], 5000);
    expect(repository.savedBudgets?['Car'], 2500);
    expect(repository.savedCurrency, 'USD');
    expect(find.textContaining('USD 1500.00 spent'), findsOneWidget);
  });

  testWidgets('refreshes when refresh token changes', (tester) async {
    final repository = _FakeMonthlyPlanRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyPlanningCard(repository: repository, refreshToken: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.fetchCount, 1);
    expect(find.textContaining('INR 1500.00 spent'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyPlanningCard(repository: repository, refreshToken: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.fetchCount, 2);
    expect(find.textContaining('INR 1750.00 spent'), findsOneWidget);
  });
}
