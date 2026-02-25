/// Utility class for date and time formatting operations.
class DateFormatter {
  /// Formats a [DateTime] to a date string in DD/MM/YYYY format.
  static String formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  /// Formats a [DateTime] to a date and time string.
  /// Example: "12/11/2025 14:30"
  static String formatDateWithTime(DateTime dateTime) {
    final date = formatDate(dateTime);
    final time = formatTime(dateTime);
    return '$date $time';
  }

  /// Formats a [DateTime] to a time string in HH:MM format.
  static String formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Checks if the given [date] is today.
  static bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Checks if the given [date] is yesterday.
  static bool isYesterday(DateTime date) {
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    return date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;
  }
}
