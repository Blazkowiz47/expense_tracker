import 'package:flutter/material.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    this.icon,
    this.label,
    this.backgroundColor,
    this.foregroundColor,
    this.size = 40,
    super.key,
  });

  final IconData? icon;
  final String? label;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedBackground =
        backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final resolvedForeground =
        foregroundColor ?? theme.colorScheme.onSurfaceVariant;
    final labelText = (label ?? '').trim();

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: resolvedBackground,
      foregroundColor: resolvedForeground,
      child: icon != null
          ? Icon(icon, size: size * 0.55)
          : Text(
              labelText.isNotEmpty ? labelText[0].toUpperCase() : '?',
              style: TextStyle(
                color: resolvedForeground,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
