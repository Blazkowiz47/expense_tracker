import '../models/group.dart';

/// Abstract interface for Groups data sources.
///
/// Implementations of this interface provide access to group data
/// from either local storage (Hive) or remote storage (Firebase).
abstract class GroupsDatasource {
  /// Initialize the datasource (e.g., open Hive box, setup Firebase listeners)
  Future<void> initialize();

  /// Close the datasource and clean up resources
  Future<void> close();

  /// Create a new group
  ///
  /// Returns the created [Group] with the generated ID
  Future<Group> createGroup(Group group);

  /// Update an existing group
  ///
  /// Returns the updated [Group]
  Future<Group> updateGroup(Group group);

  /// Delete a group by ID
  ///
  /// Soft delete by setting isActive = false, or hard delete depending on implementation
  Future<void> deleteGroup(String groupId);

  /// Get a single group by ID
  ///
  /// Returns null if the group doesn't exist
  Future<Group?> getGroup(String groupId);

  /// Get all groups where the user is a member
  ///
  /// [userId] - the ID of the user to get groups for
  /// Returns a list of groups, may be empty
  Future<List<Group>> getGroupsByUser(String userId);

  /// Add a member to a group
  ///
  /// [groupId] - the ID of the group
  /// [userId] - the ID of the user to add
  /// [userName] - the display name of the user
  /// Returns the updated [Group]
  Future<Group> addMember(String groupId, String userId, String userName);

  /// Remove a member from a group
  ///
  /// [groupId] - the ID of the group
  /// [userId] - the ID of the user to remove
  /// Returns the updated [Group]
  Future<Group> removeMember(String groupId, String userId);

  /// Get all groups (for local datasource cache purposes)
  ///
  /// Returns a list of all groups stored locally
  Future<List<Group>> getAllGroups();

  /// Save all groups (for sync purposes)
  ///
  /// [groups] - list of groups to save/update
  Future<void> saveGroups(List<Group> groups);
}
