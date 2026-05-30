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
    expect(find.text('Overview'), findsNothing);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Friends'), findsWidgets);
    expect(find.text('Family'), findsWidgets);
    expect(find.text('Groups'), findsWidgets);
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
    expect(find.text('Scan bill'), findsOneWidget);
    expect(find.text('Settle up'), findsOneWidget);
    expect(find.text('Friend'), findsNothing);
    expect(find.text('Group'), findsNothing);
  });

  testWidgets('desktop shell shows navigation rail', (tester) async {
    await pumpShell(tester, size: const Size(1400, 900));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
  });

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
