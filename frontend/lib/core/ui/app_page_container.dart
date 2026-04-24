import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

class AppPageContainer extends StatelessWidget {
  const AppPageContainer({
    required this.children,
    this.maxWidth = 900,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    super.key,
  });

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(padding: padding, children: children),
      ),
    );
  }
}
