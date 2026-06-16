import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:expense_tracker/features/planning/view/monthly_planning_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeMonthlyPlanRepository extends MonthlyPlanRepository {
  _FakeMonthlyPlanRepository({
    this.excludedExpenseCount = 0,
    this.excludedActualsByCurrency = const {},
    this.categoryExcludedExpenseCount = 0,
    this.categoryExcludedActualsByCurrency = const {},
    this.totalBudget = 5000,
    this.initialActual = 1500,
    this.refreshedActual = 1750,
    this.categories,
  }) : super(client: MockClient((_) async => http.Response('{}', 200)));

  final int excludedExpenseCount;
  final Map<String, double> excludedActualsByCurrency;
  final int categoryExcludedExpenseCount;
  final Map<String, double> categoryExcludedActualsByCurrency;
  final double totalBudget;
  final double initialActual;
  final double refreshedActual;
  final List<MonthlyPlanCategory>? categories;
  Map<String, double>? savedBudgets;
  String? savedCurrency;
  int fetchCount = 0;
  final fetchedGroupIds = <String?>[];
  String? savedGroupId;

  @override
  Future<MonthlyPlan> fetchPlan({
    required String month,
    String? groupId,
  }) async {
    fetchCount += 1;
    fetchedGroupIds.add(groupId);
    final actual = fetchCount == 1 ? initialActual : refreshedActual;
    return MonthlyPlan(
      month: '2026-06',
      groupId: groupId,
      currency: 'INR',
      totalBudget: totalBudget,
      totalActual: actual,
      totalRemaining: totalBudget - actual,
      excludedExpenseCount: excludedExpenseCount,
      excludedActualsByCurrency: excludedActualsByCurrency,
      categories:
          categories ??
          [
            MonthlyPlanCategory(
              category: 'Groceries',
              budget: totalBudget,
              actual: actual,
              remaining: totalBudget - actual,
              progress: totalBudget <= 0 ? 0 : actual / totalBudget,
              overBudget: false,
              excludedExpenseCount: categoryExcludedExpenseCount,
              excludedActualsByCurrency: categoryExcludedActualsByCurrency,
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
    String? groupId,
    required String currency,
    required Map<String, double> budgets,
  }) async {
    savedBudgets = budgets;
    savedCurrency = currency;
    savedGroupId = groupId;
    final totalBudget = budgets.values.fold<double>(
      0,
      (total, value) => total + value,
    );
    return MonthlyPlan(
      month: month,
      groupId: groupId,
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
  testWidgets('set monthly plan opens guided setup wizard', (tester) async {
    final repository = _FakeMonthlyPlanRepository(totalBudget: 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MonthlyPlanningCard(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Set monthly plan'));
    await tester.pumpAndSettle();

    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Monthly plan'), findsNothing);
  });

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
    expect(repository.savedGroupId, isNull);
    expect(find.textContaining('USD 1500.00 spent'), findsOneWidget);
  });

  testWidgets('existing cost plan shows red costs and setup action', (
    tester,
  ) async {
    final repository = _FakeMonthlyPlanRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MonthlyPlanningCard(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complete setup'), findsOneWidget);
    expect(find.text('INR 5000.00 planned costs'), findsOneWidget);
    expect(find.text('INR 1500 spent / 5000 planned'), findsOneWidget);

    final headline = tester.widget<Text>(
      find.text('INR 5000.00 planned costs'),
    );
    final rowAmount = tester.widget<Text>(
      find.text('INR 1500 spent / 5000 planned'),
    );
    final context = tester.element(find.text('INR 5000.00 planned costs'));
    final errorColor = Theme.of(context).colorScheme.error;
    expect(headline.style?.color, errorColor);
    expect(rowAmount.style?.color, errorColor);
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

  testWidgets('category add action reports selected category', (tester) async {
    final repository = _FakeMonthlyPlanRepository();
    String? selectedCategory;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyPlanningCard(
            repository: repository,
            onAddExpenseForCategory: (category) {
              selectedCategory = category;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add Groceries expense'));
    await tester.pumpAndSettle();

    expect(selectedCategory, 'Groceries');
  });

  testWidgets('category row reports selected review category', (tester) async {
    final repository = _FakeMonthlyPlanRepository();
    String? reviewedCategory;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyPlanningCard(
            repository: repository,
            onReviewCategory: (category) {
              reviewedCategory = category;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Groceries').first);
    await tester.pumpAndSettle();

    expect(reviewedCategory, 'Groceries');
  });

  testWidgets('passes household group id and reloads when it changes', (
    tester,
  ) async {
    final repository = _FakeMonthlyPlanRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyPlanningCard(
            repository: repository,
            groupId: 'family-1',
            title: 'Household plan',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.fetchedGroupIds, ['family-1']);
    expect(find.text('Household plan'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyPlanningCard(
            repository: repository,
            groupId: 'family-2',
            title: 'Household plan',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.fetchedGroupIds, ['family-1', 'family-2']);
  });

  testWidgets('shows expenses excluded from selected plan currency', (
    tester,
  ) async {
    final repository = _FakeMonthlyPlanRepository(
      excludedExpenseCount: 2,
      excludedActualsByCurrency: const {'USD': 30, 'EUR': 12},
      categoryExcludedExpenseCount: 1,
      categoryExcludedActualsByCurrency: const {'USD': 30},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MonthlyPlanningCard(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 expenses not counted in INR actuals'), findsOneWidget);
    expect(
      find.text('Outside plan currency: EUR 12.00 / USD 30.00'),
      findsOneWidget,
    );
    expect(find.text('Not counted: USD 30.00'), findsOneWidget);
  });

  testWidgets('loan category is shown as due until it is paid', (tester) async {
    final repository = _FakeMonthlyPlanRepository(
      totalBudget: 9733,
      initialActual: 0,
      refreshedActual: 0,
      categories: const [
        MonthlyPlanCategory(
          category: 'Groceries',
          budget: 6000,
          actual: 0,
          remaining: 6000,
          progress: 0,
          overBudget: false,
        ),
        MonthlyPlanCategory(
          category: 'Loans / EMI',
          budget: 3733,
          actual: 0,
          remaining: 3733,
          progress: 0,
          overBudget: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MonthlyPlanningCard(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('INR 3733.00 due in loans'), findsOneWidget);
    expect(find.text('INR 3733 due'), findsOneWidget);
    expect(find.text('Paid INR 0 of 3733'), findsOneWidget);

    final dueText = tester.widget<Text>(find.text('INR 3733 due'));
    final context = tester.element(find.text('INR 3733 due'));
    expect(dueText.style?.color, Theme.of(context).colorScheme.error);
  });
}
