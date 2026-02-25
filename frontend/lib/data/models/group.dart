import 'package:equatable/equatable.dart';

enum GroupType { split, family }

GroupType groupTypeFromString(String? raw) {
  switch (raw) {
    case 'family':
      return GroupType.family;
    case 'split':
    default:
      return GroupType.split;
  }
}

/// Represents a group of users who share expenses together.
///
/// Groups are the primary way to manage shared expenses in the app.
/// Each group has members (identified by userId) and their display names.
class Group extends Equatable {
  /// Unique identifier for the group
  final String id;

  /// Display name of the group (e.g., "Weekend Trip", "Roommates")
  final String name;

  /// User ID of the person who created the group
  final String creatorId;

  /// List of user IDs who are members of this group
  final List<String> memberIds;

  /// Map of userId to display name for each member
  /// Example: {'user_1': 'Alice', 'user_2': 'Bob'}
  final Map<String, String> memberNames;

  /// When the group was created
  final DateTime createdAt;

  /// Whether the group is currently active or archived
  final bool isActive;

  /// Group behavior mode.
  final GroupType groupType;

  const Group({
    required this.id,
    required this.name,
    required this.creatorId,
    required this.memberIds,
    required this.memberNames,
    required this.createdAt,
    required this.isActive,
    this.groupType = GroupType.split,
  });

  /// Creates a Group from a JSON map
  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      creatorId: json['creatorId'] as String,
      memberIds: List<String>.from(json['memberIds'] as List),
      memberNames: Map<String, String>.from(json['memberNames'] as Map),
      createdAt: DateTime.parse(json['createdAt'] as String),
      isActive: json['isActive'] as bool,
      groupType: groupTypeFromString(json['groupType'] as String?),
    );
  }

  /// Converts this Group to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'creatorId': creatorId,
      'memberIds': memberIds,
      'memberNames': memberNames,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive,
      'groupType': groupType.name,
    };
  }

  /// Creates a copy of this Group with the specified fields replaced
  Group copyWith({
    String? id,
    String? name,
    String? creatorId,
    List<String>? memberIds,
    Map<String, String>? memberNames,
    DateTime? createdAt,
    bool? isActive,
    GroupType? groupType,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      creatorId: creatorId ?? this.creatorId,
      memberIds: memberIds ?? this.memberIds,
      memberNames: memberNames ?? this.memberNames,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      groupType: groupType ?? this.groupType,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    creatorId,
    memberIds,
    memberNames,
    createdAt,
    isActive,
    groupType,
  ];

  @override
  String toString() {
    return 'Group(id: $id, name: $name, creatorId: $creatorId, '
        'memberIds: $memberIds, memberNames: $memberNames, '
        'createdAt: $createdAt, isActive: $isActive, groupType: $groupType)';
  }
}
