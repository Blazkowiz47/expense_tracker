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
        child: const MaterialApp(
          home: HomeShellPage(repository: MockDashboardSnapshotRepository()),
        ),
      ),
    );
  }

  testWidgets('mobile shell shows bottom nav and toggles FAB visibility', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(430, 900));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

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
