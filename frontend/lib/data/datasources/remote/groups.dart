import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/group.dart';
import '../groups.dart';

/// Firebase Firestore implementation of GroupsDatasource.
///
/// Stores groups in Firestore collection: groups/{groupId}
class FirebaseGroupsDatasource implements GroupsDatasource {
  final FirebaseFirestore firestore;

  FirebaseGroupsDatasource({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<void> initialize() async {
    // No initialization needed for Firestore
  }

  @override
  Future<void> close() async {
    // No cleanup needed for Firestore
  }

  CollectionReference get _groupsCollection => firestore.collection('groups');

  @override
  Future<Group> createGroup(Group group) async {
    await _groupsCollection.doc(group.id).set(group.toJson());
    return group;
  }

  @override
  Future<Group> updateGroup(Group group) async {
    await _groupsCollection.doc(group.id).set(group.toJson());
    return group;
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    final doc = await _groupsCollection.doc(groupId).get();
    if (doc.exists) {
      await _groupsCollection.doc(groupId).update({'isActive': false});
    }
  }

  @override
  Future<Group?> getGroup(String groupId) async {
    final doc = await _groupsCollection.doc(groupId).get();
    if (!doc.exists) return null;

    final data = doc.data() as Map<String, dynamic>;
    return Group.fromJson(data);
  }

  @override
  Future<List<Group>> getGroupsByUser(String userId) async {
    final querySnapshot = await _groupsCollection
        .where('memberIds', arrayContains: userId)
        .where('isActive', isEqualTo: true)
        .get();

    return querySnapshot.docs
        .map((doc) => Group.fromJson(doc.data() as Map<String, dynamic>))
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
    final querySnapshot = await _groupsCollection.get();

    return querySnapshot.docs
        .map((doc) => Group.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveGroups(List<Group> groups) async {
    final batch = firestore.batch();
    for (var group in groups) {
      batch.set(_groupsCollection.doc(group.id), group.toJson());
    }
    await batch.commit();
  }
}
