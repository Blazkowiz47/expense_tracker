import 'package:expense_tracker/features/groups/utils/group_transfer_simplifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns no suggestions when settled', () {
    final result = simplifyGroupTransfers({'u1': 0, 'u2': 0.002, 'u3': -0.002});

    expect(result, isEmpty);
  });

  test('creates minimal transfers for a balanced map', () {
    final result = simplifyGroupTransfers({'u1': 120, 'u2': -50, 'u3': -70});

    expect(result.length, 2);
    expect(result[0].fromUid, 'u3');
    expect(result[0].toUid, 'u1');
    expect(result[0].amount, closeTo(70, 0.001));
    expect(result[1].fromUid, 'u2');
    expect(result[1].toUid, 'u1');
    expect(result[1].amount, closeTo(50, 0.001));
  });

  test('splits across multiple creditors', () {
    final result = simplifyGroupTransfers({
      'u1': 60,
      'u2': 40,
      'u3': -30,
      'u4': -70,
    });

    expect(result.length, 3);
    final total = result.fold<double>(0, (sum, item) => sum + item.amount);
    expect(total, closeTo(100, 0.001));
  });
}
