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
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byTooltip('Add expense'), findsOneWidget);
    expect(find.text('Expense tracker'), findsWidgets);
    expect(find.text('Home'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Needs attention'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Needs attention'), findsWidgets);
    expect(find.text('Activity'), findsWidgets);
    expect(find.text('Account'), findsWidgets);

    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
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
      expect(
        tester.getTopLeft(find.text('Scan bill')).dy,
        lessThan(tester.getTopLeft(find.text('Groceries')).dy),
      );
      expect(find.byIcon(Icons.grid_view_outlined), findsWidgets);
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
      expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
      expect(find.byIcon(Icons.sync_alt), findsOneWidget);
      expect(find.byIcon(Icons.umbrella_outlined), findsOneWidget);
      expect(find.byIcon(Icons.credit_card_outlined), findsOneWidget);
      expect(find.byIcon(Icons.attach_money), findsOneWidget);
      expect(find.byIcon(Icons.group_outlined), findsWidgets);
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
