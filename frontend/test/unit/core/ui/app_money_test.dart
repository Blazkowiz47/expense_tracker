import 'package:expense_tracker/core/ui/app_money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppMoney', () {
    test('formats display amounts with rupee symbol and Indian grouping', () {
      expect(AppMoney.format(0), '₹0.00');
      expect(AppMoney.format(1250), '₹1,250.00');
      expect(AppMoney.format(1234567.8), '₹12,34,567.80');
      expect(AppMoney.format(-340), '-₹340.00');
    });

    test('normalizes INR display text', () {
      expect(
        AppMoney.normalizeDisplayText('You owe INR 553.33'),
        'You owe ₹553.33',
      );
      expect(
        AppMoney.normalizeDisplayText('You get back INR 1,933.34'),
        'You get back ₹1,933.34',
      );
    });
  });
}
