import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:expense_tracker/data/datasources/remote/groups.dart';
import 'package:expense_tracker/data/models/group.dart';

void main() {
  late FirebaseGroupsDatasource datasource;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    datasource = FirebaseGroupsDatasource(firestore: fakeFirestore);
  });

  group('FirebaseGroupsDatasource', () {
    final testDate = DateTime(2024, 1, 15, 10, 30);

    final testGroup = Group(
      id: 'group_1',
      name: 'Weekend Trip',
      creatorId: 'user_1',
      memberIds: ['user_1', 'user_2'],
      memberNames: {'user_1': 'Alice', 'user_2': 'Bob'},
      createdAt: testDate,
      isActive: true,
    );

    group('initialize and close', () {
      test('initialize completes successfully', () async {
        await datasource.initialize();
        // No error means success
      });

      test('close completes successfully', () async {
        await datasource.close();
        // No error means success
      });
    });

    group('createGroup', () {
      test('creates a new group in Firestore', () async {
        final created = await datasource.createGroup(testGroup);

        expect(created, testGroup);

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        expect(doc.exists, true);
        expect(doc.data()!['name'], 'Weekend Trip');
        expect(doc.data()!['creatorId'], 'user_1');
      });

      test('overwrites existing group with same id', () async {
        await datasource.createGroup(testGroup);

        final updated = testGroup.copyWith(name: 'Updated Trip');
        await datasource.createGroup(updated);

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        expect(doc.data()!['name'], 'Updated Trip');
      });

      test('stores memberIds as array', () async {
        await datasource.createGroup(testGroup);

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        expect(doc.data()!['memberIds'], ['user_1', 'user_2']);
      });

      test('stores memberNames as map', () async {
        await datasource.createGroup(testGroup);

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        final memberNames = doc.data()!['memberNames'] as Map;
        expect(memberNames['user_1'], 'Alice');
        expect(memberNames['user_2'], 'Bob');
      });

      test('stores timestamp as ISO string', () async {
        await datasource.createGroup(testGroup);

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        expect(doc.data()!['createdAt'], testDate.toIso8601String());
      });
    });

    group('updateGroup', () {
      test('updates an existing group', () async {
        await datasource.createGroup(testGroup);

        final updated = testGroup.copyWith(
          name: 'Updated Name',
          isActive: false,
        );
        final result = await datasource.updateGroup(updated);

        expect(result.name, 'Updated Name');
        expect(result.isActive, false);

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        expect(doc.data()!['name'], 'Updated Name');
        expect(doc.data()!['isActive'], false);
      });

      test('creates group if it does not exist', () async {
        final result = await datasource.updateGroup(testGroup);

        expect(result, testGroup);

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        expect(doc.exists, true);
      });

      test('updates memberIds and memberNames', () async {
        await datasource.createGroup(testGroup);

        final updated = testGroup.copyWith(
          memberIds: ['user_1', 'user_2', 'user_3'],
          memberNames: {
            'user_1': 'Alice',
            'user_2': 'Bob',
            'user_3': 'Charlie',
          },
        );
        await datasource.updateGroup(updated);

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        expect(doc.data()!['memberIds'], ['user_1', 'user_2', 'user_3']);
        final memberNames = doc.data()!['memberNames'] as Map;
        expect(memberNames['user_3'], 'Charlie');
      });
    });

    group('deleteGroup', () {
      test('soft deletes a group by setting isActive to false', () async {
        await datasource.createGroup(testGroup);

        await datasource.deleteGroup('group_1');

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        expect(doc.exists, true);
        expect(doc.data()!['isActive'], false);
      });

      test('does nothing if group does not exist', () async {
        // Should not throw
        await datasource.deleteGroup('nonexistent_id');

        final doc = await fakeFirestore
            .collection('groups')
            .doc('nonexistent_id')
            .get();

        expect(doc.exists, false);
      });

      test('preserves all other fields when soft deleting', () async {
        await datasource.createGroup(testGroup);

        await datasource.deleteGroup('group_1');

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        expect(doc.data()!['id'], 'group_1');
        expect(doc.data()!['name'], 'Weekend Trip');
        expect(doc.data()!['memberIds'], ['user_1', 'user_2']);
        expect(doc.data()!['isActive'], false);
      });
    });

    group('getGroup', () {
      test('retrieves an existing group by id', () async {
        await datasource.createGroup(testGroup);

        final result = await datasource.getGroup('group_1');

        expect(result, isNotNull);
        expect(result!.id, 'group_1');
        expect(result.name, 'Weekend Trip');
        expect(result.memberIds, ['user_1', 'user_2']);
      });

      test('returns null for non-existent group', () async {
        final result = await datasource.getGroup('nonexistent_id');

        expect(result, isNull);
      });

      test('retrieves group even if inactive', () async {
        final inactiveGroup = testGroup.copyWith(isActive: false);
        await datasource.createGroup(inactiveGroup);

        final result = await datasource.getGroup('group_1');

        expect(result, isNotNull);
        expect(result!.isActive, false);
      });
    });

    group('getGroupsByUser', () {
      test('returns groups where user is a member', () async {
        await datasource.createGroup(testGroup);

        final group2 = Group(
          id: 'group_2',
          name: 'Dinner Party',
          creatorId: 'user_2',
          memberIds: ['user_2', 'user_3'],
          memberNames: {'user_2': 'Bob', 'user_3': 'Charlie'},
          createdAt: testDate,
          isActive: true,
        );
        await datasource.createGroup(group2);

        final group3 = Group(
          id: 'group_3',
          name: 'Lunch',
          creatorId: 'user_1',
          memberIds: ['user_1', 'user_3'],
          memberNames: {'user_1': 'Alice', 'user_3': 'Charlie'},
          createdAt: testDate,
          isActive: true,
        );
        await datasource.createGroup(group3);

        final user1Groups = await datasource.getGroupsByUser('user_1');

        expect(user1Groups.length, 2);
        expect(user1Groups.any((g) => g.id == 'group_1'), true);
        expect(user1Groups.any((g) => g.id == 'group_3'), true);
        expect(user1Groups.any((g) => g.id == 'group_2'), false);
      });

      test('returns empty list if user is not in any groups', () async {
        await datasource.createGroup(testGroup);

        final result = await datasource.getGroupsByUser('user_99');

        expect(result, isEmpty);
      });

      test('filters out inactive groups by default', () async {
        await datasource.createGroup(testGroup);

        final inactiveGroup = Group(
          id: 'group_2',
          name: 'Old Group',
          creatorId: 'user_1',
          memberIds: ['user_1'],
          memberNames: {'user_1': 'Alice'},
          createdAt: testDate,
          isActive: false,
        );
        await datasource.createGroup(inactiveGroup);

        final result = await datasource.getGroupsByUser('user_1');

        expect(result.length, 1);
        expect(result.first.id, 'group_1');
      });

      test('returns empty list if no groups exist', () async {
        final result = await datasource.getGroupsByUser('user_1');

        expect(result, isEmpty);
      });
    });

    group('addMember', () {
      test('adds a new member to a group', () async {
        await datasource.createGroup(testGroup);

        final updated = await datasource.addMember(
          'group_1',
          'user_3',
          'Charlie',
        );

        expect(updated.memberIds, contains('user_3'));
        expect(updated.memberNames['user_3'], 'Charlie');
        expect(updated.memberIds.length, 3);

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        expect(doc.data()!['memberIds'], contains('user_3'));
      });

      test('does not duplicate existing member', () async {
        await datasource.createGroup(testGroup);

        final updated = await datasource.addMember(
          'group_1',
          'user_1',
          'Alice Updated',
        );

        expect(updated.memberIds.length, 2);
        expect(updated.memberNames['user_1'], 'Alice Updated');
      });

      test('throws if group does not exist', () async {
        expect(
          () => datasource.addMember('nonexistent_id', 'user_3', 'Charlie'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('removeMember', () {
      test('removes a member from a group', () async {
        await datasource.createGroup(testGroup);

        final updated = await datasource.removeMember('group_1', 'user_2');

        expect(updated.memberIds, isNot(contains('user_2')));
        expect(updated.memberNames.containsKey('user_2'), false);
        expect(updated.memberIds.length, 1);

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        expect(doc.data()!['memberIds'], isNot(contains('user_2')));
      });

      test('does nothing if member not in group', () async {
        await datasource.createGroup(testGroup);

        final updated = await datasource.removeMember('group_1', 'user_99');

        expect(updated.memberIds.length, 2);
      });

      test('throws if group does not exist', () async {
        expect(
          () => datasource.removeMember('nonexistent_id', 'user_1'),
          throwsA(isA<Exception>()),
        );
      });

      test('can remove all members leaving empty group', () async {
        await datasource.createGroup(testGroup);

        await datasource.removeMember('group_1', 'user_1');
        final updated = await datasource.removeMember('group_1', 'user_2');

        expect(updated.memberIds, isEmpty);
        expect(updated.memberNames, isEmpty);
      });
    });

    group('getAllGroups', () {
      test('returns all stored groups', () async {
        await datasource.createGroup(testGroup);

        final group2 = testGroup.copyWith(id: 'group_2', name: 'Dinner');
        await datasource.createGroup(group2);

        final all = await datasource.getAllGroups();

        expect(all.length, 2);
        expect(all.any((g) => g.id == 'group_1'), true);
        expect(all.any((g) => g.id == 'group_2'), true);
      });

      test('returns empty list if no groups exist', () async {
        final all = await datasource.getAllGroups();

        expect(all, isEmpty);
      });

      test('includes inactive groups', () async {
        await datasource.createGroup(testGroup);

        final inactiveGroup = testGroup.copyWith(
          id: 'group_2',
          isActive: false,
        );
        await datasource.createGroup(inactiveGroup);

        final all = await datasource.getAllGroups();

        expect(all.length, 2);
        expect(all.any((g) => g.isActive == false), true);
      });
    });

    group('saveGroups', () {
      test('saves multiple groups at once', () async {
        final group1 = testGroup;
        final group2 = testGroup.copyWith(id: 'group_2', name: 'Dinner');
        final group3 = testGroup.copyWith(id: 'group_3', name: 'Lunch');

        await datasource.saveGroups([group1, group2, group3]);

        final snapshot = await fakeFirestore.collection('groups').get();
        expect(snapshot.docs.length, 3);
      });

      test('overwrites existing groups', () async {
        await datasource.createGroup(testGroup);

        final updated = testGroup.copyWith(name: 'Updated');
        await datasource.saveGroups([updated]);

        final doc = await fakeFirestore
            .collection('groups')
            .doc('group_1')
            .get();

        expect(doc.data()!['name'], 'Updated');
      });

      test('handles empty list', () async {
        await datasource.saveGroups([]);

        final snapshot = await fakeFirestore.collection('groups').get();
        expect(snapshot.docs.length, 0);
      });
    });

    group('Edge Cases', () {
      test('handles large memberIds list', () async {
        final largeGroup = Group(
          id: 'large_group',
          name: 'Large Group',
          creatorId: 'user_1',
          memberIds: List.generate(100, (i) => 'user_$i'),
          memberNames: Map.fromEntries(
            List.generate(100, (i) => MapEntry('user_$i', 'User $i')),
          ),
          createdAt: testDate,
          isActive: true,
        );

        await datasource.createGroup(largeGroup);
        final retrieved = await datasource.getGroup('large_group');

        expect(retrieved!.memberIds.length, 100);
        expect(retrieved.memberNames.length, 100);
      });

      test('handles special characters in group data', () async {
        final specialGroup = Group(
          id: 'group_special',
          name: 'Trip 🌍 2024! @#\$%',
          creatorId: 'user_1',
          memberIds: ['user_1'],
          memberNames: {'user_1': 'Café ☕'},
          createdAt: testDate,
          isActive: true,
        );

        await datasource.createGroup(specialGroup);
        final retrieved = await datasource.getGroup('group_special');

        expect(retrieved!.name, 'Trip 🌍 2024! @#\$%');
        expect(retrieved.memberNames['user_1'], 'Café ☕');
      });
    });
  });
}
