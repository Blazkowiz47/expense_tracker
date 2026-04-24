import 'package:expense_tracker/core/ui/app_money.dart';
import 'package:flutter/material.dart';

class AppMoneyLabel extends StatelessWidget {
  const AppMoneyLabel({
    required this.text,
    this.positive = true,
    this.neutral = false,
    this.textAlign = TextAlign.right,
    super.key,
  });

  final String text;
  final bool positive;
  final bool neutral;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      AppMoney.normalizeDisplayText(text),
      textAlign: textAlign,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: AppMoney.statusColor(
          context,
          positive: positive,
          neutral: neutral,
        ),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
