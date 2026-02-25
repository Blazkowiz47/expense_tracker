import 'package:expense_tracker/core/constants/app_breakpoints.dart';
import 'package:flutter/material.dart';

class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    required this.mobile,
    this.tablet,
    this.desktop,
    super.key,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= AppBreakpoints.desktop) {
      return desktop ?? tablet ?? mobile;
    }

    if (width >= AppBreakpoints.tablet) {
      return tablet ?? desktop ?? mobile;
    }

    return mobile;
  }
}

extension ResponsiveContext on BuildContext {
  bool get isMobile => MediaQuery.sizeOf(this).width < AppBreakpoints.tablet;
  bool get isTablet =>
      MediaQuery.sizeOf(this).width >= AppBreakpoints.tablet &&
      MediaQuery.sizeOf(this).width < AppBreakpoints.desktop;
  bool get isDesktop => MediaQuery.sizeOf(this).width >= AppBreakpoints.desktop;
}
