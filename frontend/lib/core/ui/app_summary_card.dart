import 'package:expense_tracker/core/ui/app_card.dart';
import 'package:expense_tracker/core/ui/app_money.dart';
import 'package:flutter/material.dart';

class AppSummaryCard extends StatelessWidget {
  const AppSummaryCard({
    required this.title,
    required this.amount,
    this.positive = true,
    this.neutral = false,
    super.key,
  });

  final String title;
  final String amount;
  final bool positive;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            AppMoney.normalizeDisplayText(amount),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppMoney.statusColor(
                context,
                positive: positive,
                neutral: neutral,
              ),
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
