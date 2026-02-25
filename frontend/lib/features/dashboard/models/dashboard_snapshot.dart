import 'package:equatable/equatable.dart';

class DashboardSnapshot extends Equatable {
  const DashboardSnapshot({
    required this.overallLabel,
    required this.overallAmountText,
    required this.overallPositive,
    required this.friendItems,
    required this.groupItems,
    required this.activityItems,
    required this.accountName,
    required this.accountEmail,
  });

  final String overallLabel;
  final String overallAmountText;
  final bool overallPositive;
  final List<BalanceItem> friendItems;
  final List<BalanceItem> groupItems;
  final List<ActivityItem> activityItems;
  final String accountName;
  final String accountEmail;

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    List<BalanceItem> parseBalanceList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(BalanceItem.fromJson)
          .toList(growable: false);
    }

    List<ActivityItem> parseActivityList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ActivityItem.fromJson)
          .toList(growable: false);
    }

    return DashboardSnapshot(
      overallLabel: (json['overallLabel'] ?? '').toString(),
      overallAmountText: (json['overallAmountText'] ?? '').toString(),
      overallPositive: json['overallPositive'] as bool? ?? true,
      friendItems: parseBalanceList(json['friendItems']),
      groupItems: parseBalanceList(json['groupItems']),
      activityItems: parseActivityList(json['activityItems']),
      accountName: (json['accountName'] ?? '').toString(),
      accountEmail: (json['accountEmail'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [
    overallLabel,
    overallAmountText,
    overallPositive,
    friendItems,
    groupItems,
    activityItems,
    accountName,
    accountEmail,
  ];
}

class BalanceItem extends Equatable {
  const BalanceItem({
    required this.title,
    required this.subtitle,
    required this.amountText,
    required this.positive,
  });

  final String title;
  final String subtitle;
  final String amountText;
  final bool positive;

  factory BalanceItem.fromJson(Map<String, dynamic> json) {
    return BalanceItem(
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      amountText: (json['amountText'] ?? '').toString(),
      positive: json['positive'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [title, subtitle, amountText, positive];
}

class ActivityItem extends Equatable {
  const ActivityItem({
    required this.title,
    required this.subtitle,
    required this.amountText,
    required this.positive,
  });

  final String title;
  final String subtitle;
  final String amountText;
  final bool positive;

  factory ActivityItem.fromJson(Map<String, dynamic> json) {
    return ActivityItem(
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      amountText: (json['amountText'] ?? '').toString(),
      positive: json['positive'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [title, subtitle, amountText, positive];
}
