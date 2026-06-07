import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/freshness_snapshot.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';

enum ActivityFeedEntryKind { personalExpense, groupExpense, unknown }

class ActivityFeed {
  const ActivityFeed({
    required this.serverTime,
    required this.entries,
    required this.tombstones,
  });

  final DateTime serverTime;
  final List<ActivityFeedEntry> entries;
  final ActivityFeedTombstones tombstones;

  factory ActivityFeed.fromJson(Map<String, dynamic> json) {
    return ActivityFeed(
      serverTime:
          DateTime.tryParse((json['serverTime'] as String?) ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      entries: (json['entries'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ActivityFeedEntry.fromJson)
          .where((entry) => entry.kind != ActivityFeedEntryKind.unknown)
          .toList(growable: false),
      tombstones: ActivityFeedTombstones.fromJson(
        json['tombstones'] is Map<String, dynamic>
            ? json['tombstones'] as Map<String, dynamic>
            : const {},
      ),
    );
  }
}

class ActivityFeedEntry {
  const ActivityFeedEntry({
    required this.kind,
    required this.id,
    this.date,
    this.updatedAt,
    this.personalExpense,
    this.group,
    this.groupExpense,
  });

  final ActivityFeedEntryKind kind;
  final String id;
  final DateTime? date;
  final DateTime? updatedAt;
  final Expense? personalExpense;
  final GroupSummary? group;
  final GroupExpense? groupExpense;

  factory ActivityFeedEntry.fromJson(Map<String, dynamic> json) {
    final kind = _kindFromString(json['kind'] as String?);
    final expense = json['expense'] is Map<String, dynamic>
        ? json['expense'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final group = json['group'] is Map<String, dynamic>
        ? json['group'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return ActivityFeedEntry(
      kind: kind,
      id: (json['id'] as String?) ?? '',
      date: _parseUtc(json['date'] as String?),
      updatedAt: _parseUtc(json['updatedAt'] as String?),
      personalExpense: kind == ActivityFeedEntryKind.personalExpense
          ? Expense.fromBackendJson(expense)
          : null,
      group: kind == ActivityFeedEntryKind.groupExpense
          ? GroupSummary.fromJson(group)
          : null,
      groupExpense: kind == ActivityFeedEntryKind.groupExpense
          ? GroupExpense.fromJson(expense)
          : null,
    );
  }
}

class ActivityFeedTombstones {
  const ActivityFeedTombstones({
    this.personalDeletedIds = const [],
    this.groupDeleted = const [],
    this.deletedGroupIds = const [],
  });

  final List<String> personalDeletedIds;
  final List<GroupExpenseTombstone> groupDeleted;
  final List<String> deletedGroupIds;

  factory ActivityFeedTombstones.fromJson(Map<String, dynamic> json) {
    return ActivityFeedTombstones(
      personalDeletedIds:
          (json['personalDeletedIds'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
      groupDeleted: (json['groupDeleted'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GroupExpenseTombstone.fromJson)
          .where((item) => item.groupId.isNotEmpty && item.expenseId.isNotEmpty)
          .toList(growable: false),
      deletedGroupIds: (json['deletedGroupIds'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }
}

ActivityFeedEntryKind _kindFromString(String? raw) {
  return switch (raw) {
    'personalExpense' => ActivityFeedEntryKind.personalExpense,
    'groupExpense' => ActivityFeedEntryKind.groupExpense,
    _ => ActivityFeedEntryKind.unknown,
  };
}

DateTime? _parseUtc(String? raw) => DateTime.tryParse(raw ?? '')?.toUtc();
