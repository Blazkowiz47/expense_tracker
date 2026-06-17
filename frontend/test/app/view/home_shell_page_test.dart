import 'package:expense_tracker/app/view/home_shell_page.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester, {required Size size}) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const HomeShellPage(
            repository: MockDashboardSnapshotRepository(),
          ),
        ),
      ),
    );
  }

  testWidgets('mobile shell shows bottom nav and toggles FAB visibility', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(430, 900));
    await tester.pumpAndSettle();

    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(nav.destinations, hasLength(4));
    expect(
      nav.destinations.whereType<NavigationDestination>().map((d) => d.label),
      ['Home', 'Family', 'Activity', 'Account'],
    );
    expect(find.byType(FloatingActionButton), findsNWidgets(2));
    expect(find.byTooltip('Quick actions'), findsOneWidget);
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Needs attention'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Cashflow'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cashflow'), findsWidgets);
    expect(find.text('Budget focus'), findsWidgets);
    expect(find.text('Activity'), findsWidgets);
    expect(find.text('Account'), findsWidgets);

    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('mobile add action expands into quick actions', (tester) async {
    await pumpShell(tester, size: const Size(430, 900));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Quick actions'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Close quick actions'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Scan bill'), findsOneWidget);
    expect(find.text('Friend balances'), findsOneWidget);
    expect(find.text('Friend'), findsNothing);
    expect(find.text('Group'), findsNothing);
  });

  testWidgets('home scan bill asks for household or personal target', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(430, 900));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Quick actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan bill'));
    await tester.pumpAndSettle();

    expect(find.text('Where should this bill go?'), findsOneWidget);
    expect(find.text('Household bill'), findsOneWidget);
    expect(find.text('Personal bill'), findsOneWidget);
  });

  testWidgets('desktop shell shows navigation rail', (tester) async {
    await pumpShell(tester, size: const Size(1400, 900));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets(
    'wide web shell shows top navigation and visible actions',
    (tester) async {
      await pumpShell(tester, size: const Size(1400, 900));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Expense tracker'), findsOneWidget);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Scan bill'), findsOneWidget);
      expect(find.text('Price book'), findsWidgets);
      expect(find.text('Recurring'), findsWidgets);
      expect(find.text('Add expense'), findsOneWidget);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'ios mobile shell uses Cupertino tab scaffold',
    (tester) async {
      await pumpShell(tester, size: const Size(430, 900));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoTabScaffold), findsOneWidget);
      expect(find.byType(CupertinoTabBar), findsOneWidget);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );
}
