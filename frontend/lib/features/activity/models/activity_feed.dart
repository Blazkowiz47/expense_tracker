import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/freshness_snapshot.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/recurring/models/recurring_template.dart';

enum ActivityFeedEntryKind {
  personalExpense,
  groupExpense,
  friendSettlement,
  groupSettlement,
  recurringConfirmation,
  unknown,
}

class ActivityFeed {
  const ActivityFeed({
    required this.serverTime,
    required this.entries,
    required this.tombstones,
    this.hasMore = false,
    this.nextCursor,
  });

  final DateTime serverTime;
  final List<ActivityFeedEntry> entries;
  final ActivityFeedTombstones tombstones;
  final bool hasMore;
  final DateTime? nextCursor;

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
      hasMore: json['hasMore'] as bool? ?? false,
      nextCursor: _parseUtc(json['nextCursor'] as String?),
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
    this.viewerUid = '',
    this.payer,
    this.receiver,
    this.settlement,
    this.recurringOccurrence,
  });

  final ActivityFeedEntryKind kind;
  final String id;
  final DateTime? date;
  final DateTime? updatedAt;
  final Expense? personalExpense;
  final GroupSummary? group;
  final GroupExpense? groupExpense;
  final String viewerUid;
  final ActivityUser? payer;
  final ActivityUser? receiver;
  final ActivitySettlement? settlement;
  final RecurringOccurrence? recurringOccurrence;

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
      group:
          kind == ActivityFeedEntryKind.groupExpense ||
              kind == ActivityFeedEntryKind.groupSettlement
          ? GroupSummary.fromJson(group)
          : null,
      groupExpense: kind == ActivityFeedEntryKind.groupExpense
          ? GroupExpense.fromJson(expense)
          : null,
      viewerUid: (json['viewerUid'] as String?) ?? '',
      payer: _userFromJson(json['payer']),
      receiver: _userFromJson(json['receiver']),
      settlement: _settlementFromJson(json['settlement']),
      recurringOccurrence:
          kind == ActivityFeedEntryKind.recurringConfirmation &&
              json['occurrence'] is Map<String, dynamic>
          ? RecurringOccurrence.fromJson(
              json['occurrence'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class ActivityUser {
  const ActivityUser({
    required this.uid,
    required this.displayName,
    this.email = '',
  });

  final String uid;
  final String displayName;
  final String email;

  String get label {
    final name = displayName.trim();
    if (name.isNotEmpty) return name;
    final fallbackEmail = email.trim();
    if (fallbackEmail.isNotEmpty) return fallbackEmail;
    return uid.isEmpty ? 'Someone' : uid;
  }

  factory ActivityUser.fromJson(Map<String, dynamic> json) {
    return ActivityUser(
      uid: (json['uid'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
    );
  }
}

class ActivitySettlement {
  const ActivitySettlement({
    required this.id,
    required this.payerUid,
    required this.receiverUid,
    required this.amount,
    required this.currency,
    required this.date,
    required this.createdAt,
    this.updatedAt,
    this.groupId = '',
    this.note = '',
  });

  final String id;
  final String groupId;
  final String payerUid;
  final String receiverUid;
  final double amount;
  final String currency;
  final String note;
  final DateTime date;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory ActivitySettlement.fromJson(Map<String, dynamic> json) {
    return ActivitySettlement(
      id: (json['id'] as String?) ?? '',
      groupId: (json['groupId'] as String?) ?? '',
      payerUid: (json['payerUid'] as String?) ?? '',
      receiverUid: (json['receiverUid'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: _normalizeCurrency(json['currency']),
      note: (json['note'] as String?) ?? '',
      date:
          DateTime.tryParse((json['date'] as String?) ?? '')?.toUtc() ??
          DateTime.tryParse((json['createdAt'] as String?) ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      updatedAt: DateTime.tryParse(
        (json['updatedAt'] as String?) ?? '',
      )?.toUtc(),
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
    'friendSettlement' => ActivityFeedEntryKind.friendSettlement,
    'groupSettlement' => ActivityFeedEntryKind.groupSettlement,
    'recurringConfirmation' => ActivityFeedEntryKind.recurringConfirmation,
    _ => ActivityFeedEntryKind.unknown,
  };
}

DateTime? _parseUtc(String? raw) => DateTime.tryParse(raw ?? '')?.toUtc();

ActivityUser? _userFromJson(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  return ActivityUser.fromJson(raw);
}

ActivitySettlement? _settlementFromJson(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  return ActivitySettlement.fromJson(raw);
}

String _normalizeCurrency(Object? value) {
  final currency = value?.toString().trim().toUpperCase() ?? '';
  return RegExp(r'^[A-Z]{3}$').hasMatch(currency) ? currency : 'INR';
}
