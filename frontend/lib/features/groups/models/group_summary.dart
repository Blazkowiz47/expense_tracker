import 'package:expense_tracker/data/models/group.dart';

class GroupSummary {
  const GroupSummary({
    required this.id,
    required this.name,
    required this.groupType,
    required this.memberCount,
    this.pendingInviteCount = 0,
    this.pendingInvites = const [],
  });

  final String id;
  final String name;
  final GroupType groupType;
  final int memberCount;
  final int pendingInviteCount;
  final List<GroupPendingInvite> pendingInvites;

  factory GroupSummary.fromJson(Map<String, dynamic> json) {
    final rawInvites = json['pendingInvites'];
    final pendingInvites = rawInvites is List
        ? rawInvites
              .whereType<Map>()
              .map(
                (item) => GroupPendingInvite.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
        : const <GroupPendingInvite>[];
    return GroupSummary(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      groupType: groupTypeFromString(json['groupType'] as String?),
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      pendingInviteCount:
          (json['pendingInviteCount'] as num?)?.toInt() ??
          pendingInvites.length,
      pendingInvites: pendingInvites,
    );
  }
}

class GroupPendingInvite {
  const GroupPendingInvite({
    required this.contact,
    required this.emailNormalized,
    this.role = '',
  });

  final String contact;
  final String emailNormalized;
  final String role;

  factory GroupPendingInvite.fromJson(Map<String, dynamic> json) {
    return GroupPendingInvite(
      contact: (json['contact'] as String?) ?? '',
      emailNormalized: (json['emailNormalized'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
    );
  }

  String get label {
    if (contact.trim().isNotEmpty) return contact.trim();
    return emailNormalized.trim();
  }

  String get roleLabel => role.trim().isEmpty ? 'Member' : role.trim();
}
