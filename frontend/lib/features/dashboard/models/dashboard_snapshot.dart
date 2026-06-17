import 'package:equatable/equatable.dart';

class DashboardSnapshot extends Equatable {
  const DashboardSnapshot({
    required this.overallLabel,
    required this.overallAmountText,
    required this.overallPositive,
    required this.friendItems,
    required this.groupItems,
    required this.actionItems,
    required this.activityItems,
    required this.aiInsights,
    required this.accountName,
    required this.accountEmail,
  });

  final String overallLabel;
  final String overallAmountText;
  final bool overallPositive;
  final List<BalanceItem> friendItems;
  final List<BalanceItem> groupItems;
  final List<DailyActionItem> actionItems;
  final List<ActivityItem> activityItems;
  final List<AiInsight> aiInsights;
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

    List<DailyActionItem> parseActionList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(DailyActionItem.fromJson)
          .toList(growable: false);
    }

    List<AiInsight> parseAiInsights(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(AiInsight.fromJson)
          .toList(growable: false);
    }

    return DashboardSnapshot(
      overallLabel: (json['overallLabel'] ?? '').toString(),
      overallAmountText: (json['overallAmountText'] ?? '').toString(),
      overallPositive: json['overallPositive'] as bool? ?? true,
      friendItems: parseBalanceList(json['friendItems']),
      groupItems: parseBalanceList(json['groupItems']),
      actionItems: parseActionList(json['actionItems']),
      activityItems: parseActivityList(json['activityItems']),
      aiInsights: parseAiInsights(json['aiInsights']),
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
    actionItems,
    activityItems,
    aiInsights,
    accountName,
    accountEmail,
  ];
}

class AiInsight extends Equatable {
  const AiInsight({
    required this.label,
    required this.message,
    required this.tone,
    required this.actions,
  });

  final String label;
  final String message;
  final String tone;
  final List<AiInsightAction> actions;

  factory AiInsight.fromJson(Map<String, dynamic> json) {
    final rawActions = json['actions'];
    return AiInsight(
      label: (json['label'] ?? 'AI summary').toString(),
      message: (json['message'] ?? '').toString(),
      tone: (json['tone'] ?? 'neutral').toString(),
      actions: rawActions is List
          ? rawActions
                .whereType<Map<String, dynamic>>()
                .map(AiInsightAction.fromJson)
                .toList(growable: false)
          : const [],
    );
  }

  @override
  List<Object?> get props => [label, message, tone, actions];
}

class AiInsightAction extends Equatable {
  const AiInsightAction({required this.label, required this.prompt});

  final String label;
  final String prompt;

  factory AiInsightAction.fromJson(Map<String, dynamic> json) {
    return AiInsightAction(
      label: (json['label'] ?? '').toString(),
      prompt: (json['prompt'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [label, prompt];
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

class DailyActionItem extends Equatable {
  const DailyActionItem({
    required this.title,
    required this.subtitle,
    required this.severity,
    required this.destination,
    this.actionType = '',
    this.occurrenceId = '',
    this.period = '',
    this.groupId = '',
    this.expenseId = '',
    this.friendUid = '',
    this.memberUid = '',
    this.category = '',
  });

  final String title;
  final String subtitle;
  final String severity;
  final String destination;
  final String actionType;
  final String occurrenceId;
  final String period;
  final String groupId;
  final String expenseId;
  final String friendUid;
  final String memberUid;
  final String category;

  factory DailyActionItem.fromJson(Map<String, dynamic> json) {
    return DailyActionItem(
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      severity: (json['severity'] ?? 'info').toString(),
      destination: (json['destination'] ?? 'activity').toString(),
      actionType: (json['actionType'] ?? '').toString(),
      occurrenceId: (json['occurrenceId'] ?? '').toString(),
      period: (json['period'] ?? json['month'] ?? '').toString(),
      groupId: (json['groupId'] ?? '').toString(),
      expenseId: (json['expenseId'] ?? '').toString(),
      friendUid: (json['friendUid'] ?? '').toString(),
      memberUid: (json['memberUid'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [
    title,
    subtitle,
    severity,
    destination,
    actionType,
    occurrenceId,
    period,
    groupId,
    expenseId,
    friendUid,
    memberUid,
    category,
  ];
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
