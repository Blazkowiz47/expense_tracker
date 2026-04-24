import 'package:flutter/material.dart';

class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    required this.value,
    this.color,
    this.backgroundColor,
    this.height = 8,
    super.key,
  });

  final double value;
  final Color? color;
  final Color? backgroundColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clampedValue = value.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: ColoredBox(
        color: backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: clampedValue,
            child: SizedBox(
              height: height,
              child: ColoredBox(color: color ?? theme.colorScheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}
