import 'package:expense_tracker/core/utils/responsive_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpResponsive(
    WidgetTester tester, {
    required Size size,
    required Widget child,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
  }

  testWidgets('renders mobile when width is below tablet', (tester) async {
    await pumpResponsive(
      tester,
      size: const Size(500, 800),
      child: const ResponsiveLayout(
        mobile: Text('mobile'),
        tablet: Text('tablet'),
        desktop: Text('desktop'),
      ),
    );

    expect(find.text('mobile'), findsOneWidget);
    expect(find.text('tablet'), findsNothing);
    expect(find.text('desktop'), findsNothing);
  });

  testWidgets('renders tablet when width is tablet range', (tester) async {
    await pumpResponsive(
      tester,
      size: const Size(1100, 800),
      child: const ResponsiveLayout(
        mobile: Text('mobile'),
        tablet: Text('tablet'),
        desktop: Text('desktop'),
      ),
    );

    expect(find.text('tablet'), findsOneWidget);
  });

  testWidgets('renders desktop when width is desktop range', (tester) async {
    await pumpResponsive(
      tester,
      size: const Size(1400, 900),
      child: const ResponsiveLayout(
        mobile: Text('mobile'),
        tablet: Text('tablet'),
        desktop: Text('desktop'),
      ),
    );

    expect(find.text('desktop'), findsOneWidget);
  });
}
