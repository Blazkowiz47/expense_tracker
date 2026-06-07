class FreshnessSnapshot {
  const FreshnessSnapshot({required this.serverTime, required this.sections});

  final DateTime serverTime;
  final Map<String, FreshnessSection> sections;

  factory FreshnessSnapshot.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'] as Map<String, dynamic>? ?? const {};
    return FreshnessSnapshot(
      serverTime:
          DateTime.tryParse((json['serverTime'] as String?) ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      sections: rawSections.map(
        (key, value) => MapEntry(
          key,
          FreshnessSection.fromJson(
            value is Map<String, dynamic> ? value : const {},
          ),
        ),
      ),
    );
  }
}

class FreshnessSection {
  const FreshnessSection({
    required this.changed,
    this.watermark,
    this.personalDeletedIds = const [],
    this.groupDeleted = const [],
    this.deletedGroupIds = const [],
  });

  final bool changed;
  final DateTime? watermark;
  final List<String> personalDeletedIds;
  final List<GroupExpenseTombstone> groupDeleted;
  final List<String> deletedGroupIds;

  factory FreshnessSection.fromJson(Map<String, dynamic> json) {
    return FreshnessSection(
      changed: json['changed'] == true,
      watermark: DateTime.tryParse(
        (json['watermark'] as String?) ?? '',
      )?.toUtc(),
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

class GroupExpenseTombstone {
  const GroupExpenseTombstone({required this.groupId, required this.expenseId});

  final String groupId;
  final String expenseId;

  factory GroupExpenseTombstone.fromJson(Map<String, dynamic> json) {
    return GroupExpenseTombstone(
      groupId: (json['groupId'] as String?) ?? '',
      expenseId: (json['expenseId'] as String?) ?? '',
    );
  }
}
