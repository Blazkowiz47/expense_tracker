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
    String goalType = 'savings_goal',
    String familyVisibility = 'private',
    required double targetAmount,
    required String targetCurrency,
    required String sourceCurrency,
    required double monthlyTargetAmount,
    required String startMonth,
    String provider = '',
    String accountName = '',
    double expectedReturnRate = 0,
    DateTime? maturityDate,
    required String notes,
  }) async {
    createdGoal = _CreatedGoal(
      name: name,
      goalType: goalType,
      familyVisibility: familyVisibility,
      targetAmount: targetAmount,
      targetCurrency: targetCurrency,
      sourceCurrency: sourceCurrency,
      monthlyTargetAmount: monthlyTargetAmount,
      startMonth: startMonth,
      provider: provider,
      accountName: accountName,
      expectedReturnRate: expectedReturnRate,
    );
    final goal = _goal(
      id: 'created-goal',
      name: name,
      goalType: goalType,
      familyVisibility: familyVisibility,
      targetAmount: targetAmount,
      targetCurrency: targetCurrency,
      sourceCurrency: sourceCurrency,
      monthlyTargetAmount: monthlyTargetAmount,
      startMonth: startMonth,
      provider: provider,
      accountName: accountName,
      expectedReturnRate: expectedReturnRate,
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
    required this.goalType,
    required this.familyVisibility,
    required this.targetAmount,
    required this.targetCurrency,
    required this.sourceCurrency,
    required this.monthlyTargetAmount,
    required this.startMonth,
    required this.provider,
    required this.accountName,
    required this.expectedReturnRate,
  });

  final String name;
  final String goalType;
  final String familyVisibility;
  final double targetAmount;
  final String targetCurrency;
  final String sourceCurrency;
  final double monthlyTargetAmount;
  final String startMonth;
  final String provider;
  final String accountName;
  final double expectedReturnRate;
}

SavingsGoal _goal({
  String id = 'goal-1',
  String name = 'India savings',
  String goalType = 'savings_goal',
  String familyVisibility = 'private',
  String ownerLabel = '',
  double targetAmount = 300000,
  String targetCurrency = 'INR',
  String sourceCurrency = 'NOK',
  double monthlyTargetAmount = 25000,
  String startMonth = '2026-06',
  double totalSavedAmount = 0,
  String provider = '',
  String accountName = '',
  double expectedReturnRate = 0,
  String notes = '',
}) {
  return SavingsGoal(
    id: id,
    ownerUid: 'member-1',
    ownerLabel: ownerLabel,
    name: name,
    goalType: goalType,
    familyVisibility: familyVisibility,
    targetAmount: targetAmount,
    targetCurrency: targetCurrency,
    sourceCurrency: sourceCurrency,
    monthlyTargetAmount: monthlyTargetAmount,
    startMonth: startMonth,
    targetDate: null,
    maturityDate: null,
    provider: provider,
    accountName: accountName,
    expectedReturnRate: expectedReturnRate,
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
  testWidgets('adds a family-visible SIP from the empty state', (tester) async {
    final repository = _FakeSavingsRepository();
    await tester.pumpWidget(
      MaterialApp(home: SavingsPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No savings goals'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add goal'));
    await tester.pumpAndSettle();

    await tester.tap(_dropdownWithLabel('Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly SIP').last);
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'India SIP');
    await tester.enterText(fields.at(1), '300000');
    await tester.enterText(fields.at(2), '25000');
    await tester.enterText(fields.at(3), '2026-06');
    await tester.enterText(fields.at(4), 'Kuvera');
    await tester.enterText(fields.at(5), 'Nifty 50');
    await tester.enterText(fields.at(6), '12');

    await tester.ensureVisible(find.text('Show in family'));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.createdGoal?.name, 'India SIP');
    expect(repository.createdGoal?.goalType, 'sip');
    expect(repository.createdGoal?.familyVisibility, 'family');
    expect(repository.createdGoal?.targetAmount, 300000);
    expect(repository.createdGoal?.targetCurrency, 'INR');
    expect(repository.createdGoal?.sourceCurrency, 'NOK');
    expect(repository.createdGoal?.monthlyTargetAmount, 25000);
    expect(repository.createdGoal?.provider, 'Kuvera');
    expect(repository.createdGoal?.accountName, 'Nifty 50');
    expect(repository.createdGoal?.expectedReturnRate, 12);
    expect(find.text('India SIP'), findsOneWidget);
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

Finder _dropdownWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == label,
  );
}
