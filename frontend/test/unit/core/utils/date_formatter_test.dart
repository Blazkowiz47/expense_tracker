import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/utils/date_formatter.dart';

void main() {
  group('DateFormatter', () {
    test('formatDate should return formatted date string', () {
      final date = DateTime(2025, 11, 12);
      final formatted = DateFormatter.formatDate(date);

      expect(formatted, equals('12/11/2025'));
    });

    test('formatDateWithTime should return formatted date and time string', () {
      final dateTime = DateTime(2025, 11, 12, 14, 30, 45);
      final formatted = DateFormatter.formatDateWithTime(dateTime);

      expect(formatted, contains('12/11/2025'));
      expect(formatted, contains('14:30'));
    });

    test('formatTime should return formatted time string', () {
      final dateTime = DateTime(2025, 11, 12, 14, 30, 45);
      final formatted = DateFormatter.formatTime(dateTime);

      expect(formatted, equals('14:30'));
    });

    test('isToday should return true for today\'s date', () {
      final today = DateTime.now();
      expect(DateFormatter.isToday(today), isTrue);
    });

    test('isToday should return false for past date', () {
      final yesterday = DateTime.now().subtract(Duration(days: 1));
      expect(DateFormatter.isToday(yesterday), isFalse);
    });
  });
}
