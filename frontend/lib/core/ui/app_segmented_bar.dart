import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppChartSegment {
  const AppChartSegment({required this.value, required this.color, this.label});

  final double value;
  final Color color;
  final String? label;
}

class AppSegmentedBar extends StatelessWidget {
  const AppSegmentedBar({
    required this.segments,
    this.height = 10,
    this.backgroundColor,
    super.key,
  });

  final List<AppChartSegment> segments;
  final double height;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(
      0,
      (sum, segment) => sum + math.max(0, segment.value),
    );
    final resolvedBackground =
        backgroundColor ??
        Theme.of(context).colorScheme.surfaceContainerHighest;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: ColoredBox(
        color: resolvedBackground,
        child: SizedBox(
          height: height,
          child: total <= 0
              ? const SizedBox.expand()
              : Row(
                  children: segments
                      .where((segment) => segment.value > 0)
                      .map(
                        (segment) => Expanded(
                          flex: math.max(
                            1,
                            (segment.value / total * 1000).round(),
                          ),
                          child: ColoredBox(color: segment.color),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ),
    );
  }
}
