import 'package:flutter/material.dart';

class AppMoney {
  static const positiveColor = Color(0xFF1B8C67);
  static const inputPrefix = 'INR ';

  const AppMoney._();

  static String format(num amount) {
    final negative = amount < 0;
    final fixed = amount.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = _groupIndianDigits(parts.first);
    final decimal = parts.length > 1 ? parts.last : '00';
    return '${negative ? '-' : ''}₹$whole.$decimal';
  }

  static String formatCurrency(num amount, String currency) {
    final normalized = currency.trim().toUpperCase();
    if (normalized == 'INR' || normalized.isEmpty) {
      return format(amount);
    }
    final negative = amount < 0;
    final fixed = amount.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = _groupWesternDigits(parts.first);
    final decimal = parts.length > 1 ? parts.last : '00';
    return '${negative ? '-' : ''}$normalized $whole.$decimal';
  }

  static String formatCurrencyAmounts(Map<String, num> amounts) {
    final entries =
        amounts.entries
            .where((entry) => entry.key.trim().isNotEmpty)
            .where((entry) => entry.value.abs() > 0.005)
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) {
      return format(0);
    }
    return entries
        .map((entry) => formatCurrency(entry.value.abs(), entry.key))
        .join(' / ');
  }

  static String normalizeDisplayText(String value) {
    return value.replaceAllMapped(RegExp(r'\bINR\s+(-?\d[\d,]*(?:\.\d+)?)'), (
      match,
    ) {
      final rawAmount = match.group(1)?.replaceAll(',', '') ?? '';
      final amount = num.tryParse(rawAmount);
      return amount == null ? match.group(0)! : format(amount);
    });
  }

  static Color statusColor(
    BuildContext context, {
    required bool positive,
    bool neutral = false,
  }) {
    if (neutral) {
      return Theme.of(context).colorScheme.outline;
    }
    return positive ? positiveColor : Theme.of(context).colorScheme.error;
  }

  static String _groupIndianDigits(String digits) {
    if (digits.length <= 3) {
      return digits;
    }

    final lastThree = digits.substring(digits.length - 3);
    var remaining = digits.substring(0, digits.length - 3);
    final groups = <String>[];

    while (remaining.length > 2) {
      groups.insert(0, remaining.substring(remaining.length - 2));
      remaining = remaining.substring(0, remaining.length - 2);
    }
    if (remaining.isNotEmpty) {
      groups.insert(0, remaining);
    }

    return '${groups.join(',')},$lastThree';
  }

  static String _groupWesternDigits(String digits) {
    if (digits.length <= 3) {
      return digits;
    }
    final groups = <String>[];
    var remaining = digits;
    while (remaining.length > 3) {
      groups.insert(0, remaining.substring(remaining.length - 3));
      remaining = remaining.substring(0, remaining.length - 3);
    }
    if (remaining.isNotEmpty) {
      groups.insert(0, remaining);
    }
    return groups.join(',');
  }
}
