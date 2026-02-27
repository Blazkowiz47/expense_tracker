import 'package:expense_tracker/data/models/group.dart';

class GroupSummary {
  const GroupSummary({
    required this.id,
    required this.name,
    required this.groupType,
    required this.memberCount,
  });

  final String id;
  final String name;
  final GroupType groupType;
  final int memberCount;

  factory GroupSummary.fromJson(Map<String, dynamic> json) {
    return GroupSummary(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      groupType: groupTypeFromString(json['groupType'] as String?),
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
    );
  }
}
