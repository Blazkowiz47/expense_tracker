import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:expense_tracker/features/dashboard/view/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

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
        ),
        DailyActionItem(
          title: 'Groceries is over budget',
          subtitle: 'INR 150.00 over this month',
          severity: 'critical',
          destination: 'family',
        ),
      ],
      activityItems: [],
      accountName: 'Sushrut',
      accountEmail: 'sushrut@example.com',
    );
  }
}
