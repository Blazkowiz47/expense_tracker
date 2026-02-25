import 'dart:developer';

import '../datasources/groups.dart';
import '../models/group.dart';

/// Repository for managing groups with local caching and remote sync.
///
/// Provides a single source of truth for group data with:
/// - In-memory cache for fast access
/// - Local persistence for offline support
/// - Remote sync with Firebase
class GroupsRepository {
  final GroupsDatasource localDatasource;
  final GroupsDatasource remoteDatasource;

  /// In-memory cache of groups, keyed by group ID
  final Map<String, Group> _groupsCache = {};

  GroupsRepository({
    required this.localDatasource,
    required this.remoteDatasource,
  });

  /// Initialize both datasources and load groups from local storage into cache
  Future<void> initialize() async {
    await Future.wait([
      localDatasource.initialize(),
      remoteDatasource.initialize(),
    ]);

    // Load groups from local storage into cache
    final localGroups = await localDatasource.getAllGroups();
    for (var group in localGroups) {
      _groupsCache[group.id] = group;
    }
  }

  /// Close both datasources
  Future<void> close() async {
    await Future.wait([localDatasource.close(), remoteDatasource.close()]);
  }

  /// Create a new group
  ///
  /// Saves to both local and remote datasources and updates cache.
  /// Continues with local save even if remote fails.
  Future<Group> createGroup(Group group) async {
    // Save locally first (for offline support)
    await localDatasource.createGroup(group);

    // Try to save remotely, but don't block on failure
    try {
      await remoteDatasource.createGroup(group);
    } catch (e) {
      log('Remote createGroup failed: $e', level: 2);
    }

    // Update cache
    _groupsCache[group.id] = group;

    return group;
  }

  /// Update an existing group
  ///
  /// Updates both datasources and cache
  Future<Group> updateGroup(Group group) async {
    await localDatasource.updateGroup(group);

    try {
      await remoteDatasource.updateGroup(group);
    } catch (e) {
      log('Remote updateGroup failed: $e', level: 2);
    }

    // Update cache
    _groupsCache[group.id] = group;

    return group;
  }

  /// Soft delete a group (sets isActive = false)
  ///
  /// Updates both datasources and marks as inactive in cache
  Future<void> deleteGroup(String groupId) async {
    await Future.wait([
      localDatasource.deleteGroup(groupId),
      remoteDatasource.deleteGroup(groupId),
    ]);

    // Update cache to mark as inactive
    final group = _groupsCache[groupId];
    if (group != null) {
      _groupsCache[groupId] = group.copyWith(isActive: false);
    }
  }

  /// Get a group by ID from cache
  ///
  /// Returns null if not found in cache
  Group? getGroup(String groupId) {
    return _groupsCache[groupId];
  }

  /// Get all active groups where the user is a member
  ///
  /// Filters cache for groups containing userId and isActive = true
  List<Group> getUserGroups(String userId) {
    return _groupsCache.values
        .where((group) => group.isActive && group.memberIds.contains(userId))
        .toList();
  }

  /// Add a member to a group
  ///
  /// Updates both datasources and cache
  Future<Group> addMember(
    String groupId,
    String userId,
    String userName,
  ) async {
    final updatedLocal = await localDatasource.addMember(
      groupId,
      userId,
      userName,
    );

    try {
      await remoteDatasource.addMember(groupId, userId, userName);
    } catch (e) {
      log('Remote addMember failed: $e', level: 2);
    }

    // Update cache
    _groupsCache[groupId] = updatedLocal;

    return updatedLocal;
  }

  /// Remove a member from a group
  ///
  /// Updates both datasources and cache
  Future<Group> removeMember(String groupId, String userId) async {
    final updatedLocal = await localDatasource.removeMember(groupId, userId);

    try {
      await remoteDatasource.removeMember(groupId, userId);
    } catch (e) {
      log('Remote removeMember failed: $e', level: 2);
    }

    // Update cache
    _groupsCache[groupId] = updatedLocal;

    return updatedLocal;
  }

  /// Sync groups from remote for a specific user
  ///
  /// Fetches latest groups from remote, saves to local, and updates cache
  Future<void> syncGroups(String userId) async {
    final remoteGroups = await remoteDatasource.getGroupsByUser(userId);

    // Save to local storage
    await localDatasource.saveGroups(remoteGroups);

    // Update cache with remote groups
    for (var group in remoteGroups) {
      _groupsCache[group.id] = group;
    }
  }

  /// Get all groups from cache
  ///
  /// Returns a list of all groups currently in memory
  List<Group> getGroupsFromCache() {
    return _groupsCache.values.toList();
  }
}
