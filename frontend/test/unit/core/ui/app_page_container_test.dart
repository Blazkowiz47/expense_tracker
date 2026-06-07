import 'dart:async';

import 'package:expense_tracker/core/ui/app_page_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wraps content with pull to refresh when onRefresh is set', (
    tester,
  ) async {
    var refreshCount = 0;

    Future<void> handleRefresh() async {
      refreshCount += 1;
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: AppPageContainer(
            onRefresh: handleRefresh,
            children: const [SizedBox(height: 24, child: Text('Tiny content'))],
          ),
        ),
      ),
    );

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(
      tester.widget<ListView>(find.byType(ListView)).physics,
      isA<AlwaysScrollableScrollPhysics>(),
    );

    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    expect(indicator.onRefresh, same(handleRefresh));
    await indicator.onRefresh();

    expect(refreshCount, 1);
  });

  testWidgets('uses a plain list when refresh is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: const Scaffold(
          body: AppPageContainer(
            children: [SizedBox(height: 24, child: Text('Static content'))],
          ),
        ),
      ),
    );

    expect(find.byType(RefreshIndicator), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('auto refresh runs on interval without overlapping', (
    tester,
  ) async {
    var refreshCount = 0;
    var completer = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPageContainer(
            autoRefresh: true,
            refreshInterval: const Duration(milliseconds: 100),
            onAutoRefresh: () {
              refreshCount += 1;
              return completer.future;
            },
            children: const [SizedBox(height: 24, child: Text('Live data'))],
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(refreshCount, 1);

    await tester.pump(const Duration(milliseconds: 100));
    expect(refreshCount, 1);

    completer.complete();
    await tester.pump();
    completer = Completer<void>();

    await tester.pump(const Duration(milliseconds: 100));
    expect(refreshCount, 2);

    completer.complete();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
