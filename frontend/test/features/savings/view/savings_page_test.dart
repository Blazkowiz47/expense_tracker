import 'package:expense_tracker/features/savings/models/savings_goal.dart';
import 'package:expense_tracker/features/savings/repositories/api_savings_repository.dart';
import 'package:expense_tracker/features/savings/view/savings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeSavingsRepository extends ApiSavingsRepository {
  _FakeSavingsRepository({List<SavingsGoal> goals = const []})
    : _goals = List<SavingsGoal>.of(goals),
      super(client: MockClient((_) async => http.Response('{}', 200)));

  var _goals = <SavingsGoal>[];
  _CreatedGoal? createdGoal;
  String? loggedGoalId;
  double? loggedSourceAmount;
  double? loggedTargetAmount;

  @override
  Future<List<SavingsGoal>> fetchGoals({bool includeArchived = false}) async {
    return _goals.where((goal) => includeArchived || !goal.archived).toList();
  }

  @override
  Future<SavingsGoal> createGoal({
    required String name,
    required double targetAmount,
    required String targetCurrency,
    required String sourceCurrency,
    required double monthlyTargetAmount,
    required String startMonth,
    required String notes,
  }) async {
    createdGoal = _CreatedGoal(
      name: name,
      targetAmount: targetAmount,
      targetCurrency: targetCurrency,
      sourceCurrency: sourceCurrency,
      monthlyTargetAmount: monthlyTargetAmount,
      startMonth: startMonth,
    );
    final goal = _goal(
      id: 'created-goal',
      name: name,
      targetAmount: targetAmount,
      targetCurrency: targetCurrency,
      sourceCurrency: sourceCurrency,
      monthlyTargetAmount: monthlyTargetAmount,
      startMonth: startMonth,
      notes: notes,
    );
    _goals = [goal, ..._goals];
    return goal;
  }

  @override
  Future<SavingsContributionResult> addContribution({
    required String goalId,
    required double sourceAmount,
    required String sourceCurrency,
    required DateTime date,
    double? targetAmount,
    double feeAmount = 0,
    String? feeCurrency,
    String notes = '',
  }) async {
    loggedGoalId = goalId;
    loggedSourceAmount = sourceAmount;
    loggedTargetAmount = targetAmount;
    final existing = _goals.firstWhere((goal) => goal.id == goalId);
    final target = targetAmount ?? sourceAmount * 8.5;
    final updated = existing.copyWith(
      totalSavedAmount: existing.totalSavedAmount + target,
      totalSourceAmount: existing.totalSourceAmount + sourceAmount,
      remainingAmount: (existing.remainingAmount - target)
          .clamp(0, existing.targetAmount)
          .toDouble(),
      currentMonthSavedAmount: existing.currentMonthSavedAmount + target,
      contributionCount: existing.contributionCount + 1,
      lastContributionAt: date,
      progress: ((existing.totalSavedAmount + target) / existing.targetAmount)
          .clamp(0, 1.5)
          .toDouble(),
    );
    _goals = _goals
        .map((goal) => goal.id == goalId ? updated : goal)
        .toList(growable: false);
    return SavingsContributionResult(
      goal: updated,
      contribution: SavingsContribution(
        id: 'contribution-1',
        goalId: goalId,
        sourceAmount: sourceAmount,
        sourceCurrency: sourceCurrency,
        targetAmount: target,
        targetCurrency: existing.targetCurrency,
        feeAmount: feeAmount,
        feeCurrency: feeCurrency ?? sourceCurrency,
        exchangeRate: target / sourceAmount,
        marketRate: 8.5,
        marketTargetAmount: sourceAmount * 8.5,
        exchangeRateProvider: 'fake-fx',
        exchangeRateFetchedAt: date,
        exchangeRateAsOf: date,
        date: date,
        notes: notes,
        createdAt: date,
        updatedAt: date,
      ),
    );
  }
}

class _CreatedGoal {
  const _CreatedGoal({
    required this.name,
    required this.targetAmount,
    required this.targetCurrency,
    required this.sourceCurrency,
    required this.monthlyTargetAmount,
    required this.startMonth,
  });

  final String name;
  final double targetAmount;
  final String targetCurrency;
  final String sourceCurrency;
  final double monthlyTargetAmount;
  final String startMonth;
}

SavingsGoal _goal({
  String id = 'goal-1',
  String name = 'India savings',
  double targetAmount = 300000,
  String targetCurrency = 'INR',
  String sourceCurrency = 'NOK',
  double monthlyTargetAmount = 25000,
  String startMonth = '2026-06',
  double totalSavedAmount = 0,
  String notes = '',
}) {
  return SavingsGoal(
    id: id,
    name: name,
    targetAmount: targetAmount,
    targetCurrency: targetCurrency,
    sourceCurrency: sourceCurrency,
    monthlyTargetAmount: monthlyTargetAmount,
    startMonth: startMonth,
    targetDate: null,
    totalSavedAmount: totalSavedAmount,
    totalSourceAmount: 0,
    remainingAmount: targetAmount - totalSavedAmount,
    progress: targetAmount <= 0 ? 0 : totalSavedAmount / targetAmount,
    currentMonthSavedAmount: 0,
    contributionCount: 0,
    lastContributionAt: null,
    notes: notes,
    archived: false,
    archivedAt: null,
    createdAt: DateTime.utc(2026, 6, 1),
    updatedAt: DateTime.utc(2026, 6, 1),
  );
}

void main() {
  testWidgets('adds a savings goal from the empty state', (tester) async {
    final repository = _FakeSavingsRepository();
    await tester.pumpWidget(
      MaterialApp(home: SavingsPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No savings goals'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add goal'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'India savings');
    await tester.enterText(fields.at(1), '300000');
    await tester.enterText(fields.at(2), '25000');
    await tester.enterText(fields.at(3), '2026-06');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.createdGoal?.name, 'India savings');
    expect(repository.createdGoal?.targetAmount, 300000);
    expect(repository.createdGoal?.targetCurrency, 'INR');
    expect(repository.createdGoal?.sourceCurrency, 'NOK');
    expect(repository.createdGoal?.monthlyTargetAmount, 25000);
    expect(find.text('India savings'), findsOneWidget);
  });

  testWidgets('logs a cross-currency saving contribution', (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeSavingsRepository(goals: [_goal()]);
    await tester.pumpWidget(
      MaterialApp(home: SavingsPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    final logButton = find.widgetWithText(FilledButton, 'Log saving');
    await tester.ensureVisible(logButton);
    await tester.tap(logButton);
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '1000');
    await tester.enterText(fields.at(1), '8500');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.loggedGoalId, 'goal-1');
    expect(repository.loggedSourceAmount, 1000);
    expect(repository.loggedTargetAmount, 8500);
    expect(find.textContaining('Saved: ₹8,500.00'), findsOneWidget);
    expect(find.text('Saving logged.'), findsOneWidget);
  });
}
