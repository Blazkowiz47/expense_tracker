import 'package:expense_tracker/features/dashboard/repositories/api_dashboard_snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('maps backend snapshot payload into dashboard snapshot', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/v1/dashboard/snapshot')) {
        return http.Response(
          '{"overallLabel":"Overall, you are owed","overallAmountText":"INR 113.33","overallPositive":true,"friendItems":[{"title":"Groceries","subtitle":"category total","amountText":"INR 100.00","positive":true}],"groupItems":[{"title":"Groceries","subtitle":"category total","amountText":"INR 100.00","positive":true}],"activityItems":[{"title":"Groceries 1","subtitle":"2026-02-24T11:00:00Z","amountText":"You owe INR 50.00","positive":false}],"accountName":"Local User","accountEmail":"uid-1@local"}',
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final repository = ApiDashboardSnapshotRepository(client: client);
    final snapshot = await repository.fetchSnapshot();

    expect(snapshot.overallLabel, 'Overall, you are owed');
    expect(snapshot.overallAmountText, 'INR 113.33');
    expect(snapshot.groupItems.first.title, 'Groceries');
    expect(snapshot.activityItems.first.title, 'Groceries 1');
  });
}
