import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DashboardOverallSummaryCard extends StatelessWidget {
  const DashboardOverallSummaryCard({
    this.fallbackTitle = "You're all settled up",
    this.fallbackAmount = '₹0.00',
    this.fallbackPositive = true,
    this.fallbackNeutral = true,
    super.key,
  });

  final String fallbackTitle;
  final String fallbackAmount;
  final bool fallbackPositive;
  final bool fallbackNeutral;

  @override
  Widget build(BuildContext context) {
    final state = context.select(
      (DashboardSnapshotCubit? cubit) => cubit?.state,
    );
    if (state is DashboardSnapshotLoaded) {
      return AppSummaryCard(
        title: state.snapshot.overallLabel,
        amount: state.snapshot.overallAmountText,
        positive: state.snapshot.overallPositive,
        neutral: state.snapshot.overallLabel.toLowerCase().contains('settled'),
      );
    }

    return AppSummaryCard(
      title: fallbackTitle,
      amount: fallbackAmount,
      positive: fallbackPositive,
      neutral: fallbackNeutral,
    );
  }
}
