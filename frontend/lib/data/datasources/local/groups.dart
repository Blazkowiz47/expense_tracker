import 'package:hive_flutter/hive_flutter.dart';
import '../../models/group.dart';
import '../groups.dart';

/// Hive implementation of GroupsDatasource for local storage.
///
/// Stores groups as JSON maps in a Hive box.
class HiveGroupsDatasource implements GroupsDatasource {
  final String boxName;
  Box<dynamic>? _box;

  HiveGroupsDatasource({this.boxName = 'groups'});

  @override
  Future<void> initialize() async {
    if (_box == null || !_box!.isOpen) {
      _box = await Hive.openBox(boxName);
    }
  }

  @override
  Future<void> close() async {
    if (_box != null && _box!.isOpen) {
      await _box!.close();
      _box = null;
    }
  }

  Box<dynamic> get _openBox {
    if (_box == null || !_box!.isOpen) {
      throw Exception(
        'HiveGroupsDatasource not initialized. Call initialize() first.',
      );
    }
    return _box!;
  }

  @override
  Future<Group> createGroup(Group group) async {
    await _openBox.put(group.id, group.toJson());
    return group;
  }

  @override
  Future<Group> updateGroup(Group group) async {
    await _openBox.put(group.id, group.toJson());
    return group;
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    final json = _openBox.get(groupId);
    if (json != null) {
      final group = Group.fromJson(Map<String, dynamic>.from(json as Map));
      final updated = group.copyWith(isActive: false);
      await _openBox.put(groupId, updated.toJson());
    }
  }

  @override
  Future<Group?> getGroup(String groupId) async {
    final json = _openBox.get(groupId);
    if (json == null) return null;
    return Group.fromJson(Map<String, dynamic>.from(json as Map));
  }

  @override
  Future<List<Group>> getGroupsByUser(String userId) async {
    final allGroups = await getAllGroups();
    return allGroups
        .where((group) => group.isActive && group.memberIds.contains(userId))
        .toList();
  }

  @override
  Future<Group> addMember(
    String groupId,
    String userId,
    String userName,
  ) async {
    final group = await getGroup(groupId);
    if (group == null) {
      throw Exception('Group with id $groupId not found');
    }

    final updatedMemberIds = List<String>.from(group.memberIds);
    if (!updatedMemberIds.contains(userId)) {
      updatedMemberIds.add(userId);
    }

    final updatedMemberNames = Map<String, String>.from(group.memberNames);
    updatedMemberNames[userId] = userName;

    final updated = group.copyWith(
      memberIds: updatedMemberIds,
      memberNames: updatedMemberNames,
    );

    await updateGroup(updated);
    return updated;
  }

  @override
  Future<Group> removeMember(String groupId, String userId) async {
    final group = await getGroup(groupId);
    if (group == null) {
      throw Exception('Group with id $groupId not found');
    }

    final updatedMemberIds = List<String>.from(group.memberIds)..remove(userId);

    final updatedMemberNames = Map<String, String>.from(group.memberNames)
      ..remove(userId);

    final updated = group.copyWith(
      memberIds: updatedMemberIds,
      memberNames: updatedMemberNames,
    );

    await updateGroup(updated);
    return updated;
  }

  @override
  Future<List<Group>> getAllGroups() async {
    final groups = <Group>[];
    for (var key in _openBox.keys) {
      final json = _openBox.get(key);
      if (json != null) {
        groups.add(Group.fromJson(Map<String, dynamic>.from(json as Map)));
      }
    }
    return groups;
  }

  @override
  Future<void> saveGroups(List<Group> groups) async {
    for (var group in groups) {
      await _openBox.put(group.id, group.toJson());
    }
  }
}
