import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';

abstract class DashboardSnapshotRepository {
  Future<DashboardSnapshot> fetchSnapshot();
}

class MockDashboardSnapshotRepository implements DashboardSnapshotRepository {
  const MockDashboardSnapshotRepository();

  @override
  Future<DashboardSnapshot> fetchSnapshot() async {
    return const DashboardSnapshot(
      overallLabel: 'Overall, you are owed',
      overallAmountText: 'INR 113.33',
      overallPositive: true,
      friendItems: [
        BalanceItem(
          title: 'Shikhar Uttam',
          subtitle: 'owes you',
          amountText: 'INR 113.33',
          positive: true,
        ),
      ],
      groupItems: [
        BalanceItem(
          title: 'This Group',
          subtitle: 'Shikhar U. owes you',
          amountText: 'INR 113.33',
          positive: true,
        ),
        BalanceItem(
          title: 'Non-group expenses',
          subtitle: 'settled up',
          amountText: 'INR 0.00',
          positive: false,
        ),
      ],
      activityItems: [
        ActivityItem(
          title: 'Shikhar U. added "Groceries 5" in "This Group"',
          subtitle: '8 Feb 2026 at 18:54',
          amountText: 'You owe INR 553.33',
          positive: false,
        ),
        ActivityItem(
          title: 'You added "Groceries 4" in "This Group"',
          subtitle: '8 Feb 2026 at 18:02',
          amountText: 'You get back INR 1,933.34',
          positive: true,
        ),
      ],
      accountName: 'Sushrut Patwardhan',
      accountEmail: 'sushrutpatwardhan@gmail.com',
    );
  }
}
