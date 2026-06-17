import 'package:expense_tracker/data/models/freshness_snapshot.dart';
import 'package:expense_tracker/data/repositories/freshness_repository.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:expense_tracker/features/dashboard/view/home_page.dart';
import 'package:expense_tracker/features/planning/models/monthly_plan.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('home page renders daily action items and opens targets', (
    tester,
  ) async {
    final cubit = DashboardSnapshotCubit(
      repository: const _ActionSnapshotRepository(),
    );
    await cubit.load();
    addTearDown(cubit.close);
    var recurringOpened = false;
    var familyOpened = false;

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          home: Scaffold(
            body: HomePage(
              onOpenRecurring: () => recurringOpened = true,
              onOpenFamily: () => familyOpened = true,
              monthlyPlanRepository: _FakeMonthlyPlanRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Needs attention'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Needs attention'), findsWidgets);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Confirm rent'), findsOneWidget);
    expect(find.text('Groceries is over budget'), findsOneWidget);

    await tester.ensureVisible(find.text('Confirm rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm rent'));
    await tester.pump();
    expect(recurringOpened, isTrue);

    await tester.ensureVisible(find.text('Groceries is over budget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groceries is over budget'));
    await tester.pump();
    expect(familyOpened, isTrue);
  });

  testWidgets('home page forwards structured daily action item', (
    tester,
  ) async {
    final cubit = DashboardSnapshotCubit(
      repository: const _ActionSnapshotRepository(),
    );
    await cubit.load();
    addTearDown(cubit.close);
    DailyActionItem? openedAction;

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          home: Scaffold(
            body: HomePage(
              onOpenAction: (item) => openedAction = item,
              monthlyPlanRepository: _FakeMonthlyPlanRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Confirm rent'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Confirm rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm rent'));
    await tester.pump();

    expect(openedAction?.actionType, 'confirm_recurring');
    expect(openedAction?.occurrenceId, 'occ-rent');
    expect(openedAction?.period, '2026-05');
  });

  testWidgets('home page shows income and surplus cashflow rows', (
    tester,
  ) async {
    final cubit = DashboardSnapshotCubit(
      repository: const _ActionSnapshotRepository(),
    );
    await cubit.load();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          home: Scaffold(
            body: HomePage(
              monthlyPlanRepository: _FakeMonthlyPlanRepository(
                plan: const MonthlyPlan(
                  month: '2026-06',
                  currency: 'NOK',
                  totalBudget: 12294,
                  totalActual: 0,
                  totalRemaining: 12294,
                  income: 36000,
                  surplus: 23706,
                  categories: [
                    MonthlyPlanCategory(
                      category: 'Rent and housing',
                      budget: 8000,
                      actual: 0,
                      remaining: 8000,
                      progress: 0,
                      overBudget: false,
                    ),
                    MonthlyPlanCategory(
                      category: 'Loans / EMI',
                      budget: 4294,
                      actual: 0,
                      remaining: 4294,
                      progress: 0,
                      overBudget: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Cashflow — June'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Surplus'), findsOneWidget);
    expect(find.text('Net surplus after all planned costs'), findsOneWidget);
    expect(find.text('NOK 36,000'), findsOneWidget);
    expect(find.text('NOK 23,706'), findsNWidgets(2));
    expect(
      tester
          .widgetList<Text>(find.text('NOK 4,294'))
          .map((widget) => widget.style?.color),
      contains(
        Theme.of(
          tester.element(find.text('Cashflow — June')),
        ).colorScheme.onSurface,
      ),
    );
  });

  testWidgets('home page shows all planned setup categories', (tester) async {
    final cubit = DashboardSnapshotCubit(
      repository: const _EmptySnapshotRepository(),
    );
    await cubit.load();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          home: Scaffold(
            body: HomePage(
              monthlyPlanRepository: _FakeMonthlyPlanRepository(
                plan: const MonthlyPlan(
                  month: '2026-06',
                  currency: 'NOK',
                  totalBudget: 28625,
                  totalActual: 0,
                  totalRemaining: 28625,
                  income: 36000,
                  surplus: 7375,
                  categories: [
                    MonthlyPlanCategory(
                      category: 'Rent and housing',
                      budget: 8000,
                      actual: 0,
                      remaining: 8000,
                      progress: 0,
                      overBudget: false,
                    ),
                    MonthlyPlanCategory(
                      category: 'Loans / EMI',
                      budget: 4294,
                      actual: 0,
                      remaining: 4294,
                      progress: 0,
                      overBudget: false,
                    ),
                    MonthlyPlanCategory(
                      category: 'Insurance',
                      budget: 1600,
                      actual: 0,
                      remaining: 1600,
                      progress: 0,
                      overBudget: false,
                    ),
                    MonthlyPlanCategory(
                      category: 'Groceries',
                      budget: 4200,
                      actual: 0,
                      remaining: 4200,
                      progress: 0,
                      overBudget: false,
                    ),
                    MonthlyPlanCategory(
                      category: 'Utilities',
                      budget: 1200,
                      actual: 0,
                      remaining: 1200,
                      progress: 0,
                      overBudget: false,
                    ),
                    MonthlyPlanCategory(
                      category: 'Subscriptions',
                      budget: 600,
                      actual: 0,
                      remaining: 600,
                      progress: 0,
                      overBudget: false,
                    ),
                    MonthlyPlanCategory(
                      category: 'Memberships',
                      budget: 900,
                      actual: 0,
                      remaining: 900,
                      progress: 0,
                      overBudget: false,
                    ),
                    MonthlyPlanCategory(
                      category: 'Transport',
                      budget: 1800,
                      actual: 0,
                      remaining: 1800,
                      progress: 0,
                      overBudget: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Planned costs by category'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Insurance'), findsOneWidget);
    expect(find.text('Memberships'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
  });

  testWidgets('home page shows complete onboarding in needs attention', (
    tester,
  ) async {
    final cubit = DashboardSnapshotCubit(
      repository: const _EmptySnapshotRepository(),
    );
    await cubit.load();
    addTearDown(cubit.close);
    var setupOpened = false;

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          home: Scaffold(
            body: HomePage(
              showContinueSetup: true,
              onContinueSetup: () => setupOpened = true,
              monthlyPlanRepository: _FakeMonthlyPlanRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Complete onboarding'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Needs attention'), findsWidgets);
    expect(find.text('1 items'), findsOneWidget);
    expect(find.text('Complete onboarding'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('needs-attention-card-continue-onboarding'),
            ),
          )
          .width,
      greaterThan(700),
    );
    expect(
      find.text(
        'Finish onboarding so budgets, bills, and savings stay aligned.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Complete onboarding'));
    await tester.pump();

    expect(setupOpened, isTrue);
  });

  testWidgets('home page infers incomplete setup from partial monthly plan', (
    tester,
  ) async {
    final cubit = DashboardSnapshotCubit(
      repository: const _EmptySnapshotRepository(),
    );
    await cubit.load();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          home: Scaffold(
            body: HomePage(
              inferIncompleteSetup: true,
              monthlyPlanRepository: _FakeMonthlyPlanRepository(
                plan: const MonthlyPlan(
                  month: '2026-06',
                  currency: 'NOK',
                  totalBudget: 12294,
                  totalActual: 0,
                  totalRemaining: 12294,
                  income: 36000,
                  surplus: 23706,
                  categories: [
                    MonthlyPlanCategory(
                      category: 'Rent and housing',
                      budget: 8000,
                      actual: 0,
                      remaining: 8000,
                      progress: 0,
                      overBudget: false,
                    ),
                    MonthlyPlanCategory(
                      category: 'Loans / EMI',
                      budget: 4294,
                      actual: 0,
                      remaining: 4294,
                      progress: 0,
                      overBudget: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Complete onboarding'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Complete onboarding'), findsOneWidget);
    expect(find.text('1 items'), findsOneWidget);
  });

  testWidgets('home auto-refresh skips reload when dashboard is fresh', (
    tester,
  ) async {
    final repository = _CountingSnapshotRepository();
    final cubit = DashboardSnapshotCubit(repository: repository);
    await cubit.load();
    addTearDown(cubit.close);
    final freshnessRepository = _FakeFreshnessRepository([
      _freshness(
        DateTime.parse('2026-06-07T10:00:00Z'),
        dashboardChanged: false,
        plansChanged: false,
      ),
      _freshness(
        DateTime.parse('2026-06-07T10:00:45Z'),
        dashboardChanged: false,
        plansChanged: false,
      ),
    ]);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          home: Scaffold(
            body: HomePage(
              autoRefresh: true,
              freshnessRepository: freshnessRepository,
              monthlyPlanRepository: _FakeMonthlyPlanRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(seconds: 45));
    await tester.pump();

    expect(repository.fetchCount, 1);
    expect(freshnessRepository.requests, hasLength(2));
    expect(freshnessRepository.requests.last.sections, ['dashboard', 'plans']);
    expect(
      freshnessRepository.requests.last.since,
      DateTime.parse('2026-06-07T10:00:00Z'),
    );
  });
}

class _EmptySnapshotRepository implements DashboardSnapshotRepository {
  const _EmptySnapshotRepository();

  @override
  Future<DashboardSnapshot> fetchSnapshot() async {
    return const DashboardSnapshot(
      overallLabel: "You're all settled up",
      overallAmountText: 'INR 0.00',
      overallPositive: true,
      friendItems: [],
      groupItems: [],
      actionItems: [],
      activityItems: [],
      accountName: 'Sushrut',
      accountEmail: 'sushrut@example.com',
    );
  }
}

class _ActionSnapshotRepository implements DashboardSnapshotRepository {
  const _ActionSnapshotRepository();

  @override
  Future<DashboardSnapshot> fetchSnapshot() async {
    return const DashboardSnapshot(
      overallLabel: "You're all settled up",
      overallAmountText: 'INR 0.00',
      overallPositive: true,
      friendItems: [],
      groupItems: [],
      actionItems: [
        DailyActionItem(
          title: 'Confirm rent',
          subtitle: 'Due today - INR 12000.00',
          severity: 'info',
          destination: 'recurring',
          actionType: 'confirm_recurring',
          occurrenceId: 'occ-rent',
          period: '2026-05',
        ),
        DailyActionItem(
          title: 'Groceries is over budget',
          subtitle: 'INR 150.00 over this month',
          severity: 'critical',
          destination: 'family',
          actionType: 'review_budget_category',
          category: 'Groceries',
        ),
      ],
      activityItems: [],
      accountName: 'Sushrut',
      accountEmail: 'sushrut@example.com',
    );
  }
}

class _CountingSnapshotRepository implements DashboardSnapshotRepository {
  int fetchCount = 0;

  @override
  Future<DashboardSnapshot> fetchSnapshot() async {
    fetchCount += 1;
    return const _ActionSnapshotRepository().fetchSnapshot();
  }
}

class _FakeMonthlyPlanRepository extends MonthlyPlanRepository {
  _FakeMonthlyPlanRepository({this.plan})
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  final MonthlyPlan? plan;

  @override
  Future<MonthlyPlan> fetchPlan({
    required String month,
    String? groupId,
  }) async {
    final existingPlan = plan;
    if (existingPlan != null) {
      return existingPlan;
    }
    return MonthlyPlan(
      month: month,
      currency: 'INR',
      totalBudget: 0,
      totalActual: 0,
      totalRemaining: 0,
      categories: const [],
    );
  }
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

FreshnessSnapshot _freshness(
  DateTime serverTime, {
  bool dashboardChanged = false,
  bool plansChanged = false,
}) {
  return FreshnessSnapshot(
    serverTime: serverTime,
    sections: {
      'dashboard': FreshnessSection(changed: dashboardChanged),
      'plans': FreshnessSection(changed: plansChanged),
    },
  );
}
