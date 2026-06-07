import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

class AppPageContainer extends StatelessWidget {
  const AppPageContainer({
    required this.children,
    this.maxWidth = 900,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onRefresh,
    super.key,
  });

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final RefreshCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final listView = ListView(
      padding: padding,
      physics: onRefresh == null ? null : const AlwaysScrollableScrollPhysics(),
      children: children,
    );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: onRefresh == null
            ? listView
            : RefreshIndicator.adaptive(onRefresh: onRefresh!, child: listView),
      ),
    );
  }
}
