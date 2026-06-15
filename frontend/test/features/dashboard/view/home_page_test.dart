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
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Confirm rent'), findsOneWidget);
    expect(find.text('Groceries is over budget'), findsOneWidget);

    await tester.tap(find.text('Confirm rent'));
    await tester.pump();
    expect(recurringOpened, isTrue);

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
            body: HomePage(onOpenAction: (item) => openedAction = item),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Confirm rent'));
    await tester.pump();

    expect(openedAction?.actionType, 'confirm_recurring');
    expect(openedAction?.occurrenceId, 'occ-rent');
    expect(openedAction?.period, '2026-05');
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
  _FakeMonthlyPlanRepository()
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  @override
  Future<MonthlyPlan> fetchPlan({
    required String month,
    String? groupId,
  }) async {
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
