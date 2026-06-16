import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DashboardOverallSummaryCard extends StatelessWidget {
  const DashboardOverallSummaryCard({
    this.fallbackTitle = 'Shared balances',
    this.fallbackAmount = 'All settled',
    this.fallbackSupportingText = 'Across friends and split groups',
    this.fallbackPositive = true,
    this.fallbackNeutral = true,
    super.key,
  });

  final String fallbackTitle;
  final String fallbackAmount;
  final String fallbackSupportingText;
  final bool fallbackPositive;
  final bool fallbackNeutral;

  @override
  Widget build(BuildContext context) {
    final state = context.select(
      (DashboardSnapshotCubit? cubit) => cubit?.state,
    );
    if (state is DashboardSnapshotLoaded) {
      final amount = state.snapshot.overallAmountText.trim().isEmpty
          ? fallbackAmount
          : state.snapshot.overallAmountText.trim();
      final amountLower = amount.toLowerCase();
      return AppSummaryCard(
        title: state.snapshot.overallLabel.trim().isEmpty
            ? fallbackTitle
            : state.snapshot.overallLabel.trim(),
        amount: amount,
        supportingText: fallbackSupportingText,
        positive: state.snapshot.overallPositive,
        neutral:
            amountLower.contains('settled') || amountLower.contains('mixed'),
      );
    }

    return AppSummaryCard(
      title: fallbackTitle,
      amount: fallbackAmount,
      supportingText: fallbackSupportingText,
      positive: fallbackPositive,
      neutral: fallbackNeutral,
    );
  }
}
