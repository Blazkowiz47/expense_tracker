import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';

abstract class DashboardSnapshotRepository {
  Future<DashboardSnapshot> fetchSnapshot();
}

class MockDashboardSnapshotRepository implements DashboardSnapshotRepository {
  const MockDashboardSnapshotRepository();

  @override
  Future<DashboardSnapshot> fetchSnapshot() async {
    return const DashboardSnapshot(
      overallLabel: 'Shared balances',
      overallAmountText: 'You are owed NOK 113.33',
      overallPositive: true,
      friendItems: [
        BalanceItem(
          title: 'Shikhar Uttam',
          subtitle: 'owes you',
          amountText: 'NOK 113.33',
          positive: true,
        ),
      ],
      groupItems: [
        BalanceItem(
          title: 'This Group',
          subtitle: 'Shikhar U. owes you',
          amountText: 'NOK 113.33',
          positive: true,
        ),
        BalanceItem(
          title: 'Non-group expenses',
          subtitle: 'settled up',
          amountText: 'NOK 0.00',
          positive: false,
        ),
      ],
      actionItems: [
        DailyActionItem(
          title: 'Confirm rent',
          subtitle: 'Due today - INR 12500.00',
          severity: 'info',
          destination: 'recurring',
        ),
        DailyActionItem(
          title: 'Groceries is over budget',
          subtitle: 'INR 420.00 over this month',
          severity: 'critical',
          destination: 'family',
          actionType: 'review_budget_category',
          category: 'Groceries',
        ),
      ],
      activityItems: [
        ActivityItem(
          title: 'Shikhar U. added "Groceries 5" in "This Group"',
          subtitle: '8 Feb 2026 at 18:54',
          amountText: 'You owe ₹553.33',
          positive: false,
        ),
        ActivityItem(
          title: 'You added "Groceries 4" in "This Group"',
          subtitle: '8 Feb 2026 at 18:02',
          amountText: 'You get back ₹1,933.34',
          positive: true,
        ),
      ],
      accountName: 'Sushrut Patwardhan',
      accountEmail: 'sushrutpatwardhan@gmail.com',
    );
  }
}
