import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:expense_tracker/data/datasources/local/groups.dart';
import 'package:expense_tracker/data/models/group.dart';

void main() {
  late HiveGroupsDatasource datasource;
  late Box<dynamic> testBox;
  late Directory testDir;

  setUpAll(() async {
    // Create a temp directory for Hive tests
    testDir = Directory.systemTemp.createTempSync('hive_groups_test_');
    Hive.init(testDir.path);
  });

  setUp(() async {
    // Delete any existing test box
    if (Hive.isBoxOpen('test_groups')) {
      await Hive.box('test_groups').clear();
      await Hive.box('test_groups').close();
    }
    await Hive.deleteBoxFromDisk('test_groups');

    // Create datasource with test box name
    datasource = HiveGroupsDatasource(boxName: 'test_groups');
    await datasource.initialize();

    testBox = Hive.box('test_groups');
  });

  tearDown(() async {
    await datasource.close();
    await Hive.deleteBoxFromDisk('test_groups');
  });

  tearDownAll(() async {
    // Clean up temp directory
    if (testDir.existsSync()) {
      testDir.deleteSync(recursive: true);
    }
  });

  group('HiveGroupsDatasource', () {
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
      test('initialize opens Hive box', () async {
        expect(Hive.isBoxOpen('test_groups'), true);
        expect(testBox, isNotNull);
      });

      test('close closes Hive box', () async {
        await datasource.close();
        expect(Hive.isBoxOpen('test_groups'), false);
      });

      test('can initialize multiple times safely', () async {
        await datasource.initialize();
        await datasource.initialize();
        expect(Hive.isBoxOpen('test_groups'), true);
      });
    });

    group('createGroup', () {
      test('creates and stores a new group', () async {
        final created = await datasource.createGroup(testGroup);

        expect(created, testGroup);
        expect(testBox.length, 1);

        final stored = testBox.get('group_1');
        expect(stored, isNotNull);
        expect(stored['id'], 'group_1');
        expect(stored['name'], 'Weekend Trip');
      });

      test('overwrites existing group with same id', () async {
        await datasource.createGroup(testGroup);

        final updated = testGroup.copyWith(name: 'Updated Trip');
        await datasource.createGroup(updated);

        expect(testBox.length, 1);
        final stored = testBox.get('group_1');
        expect(stored['name'], 'Updated Trip');
      });

      test('can create multiple groups', () async {
        await datasource.createGroup(testGroup);

        final group2 = testGroup.copyWith(id: 'group_2', name: 'Dinner');
        await datasource.createGroup(group2);

        expect(testBox.length, 2);
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

        final stored = testBox.get('group_1');
        expect(stored['name'], 'Updated Name');
        expect(stored['isActive'], false);
      });

      test('creates group if it does not exist', () async {
        final result = await datasource.updateGroup(testGroup);

        expect(result, testGroup);
        expect(testBox.length, 1);
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

        final stored = testBox.get('group_1');
        expect(stored['memberIds'], ['user_1', 'user_2', 'user_3']);
        expect(stored['memberNames']['user_3'], 'Charlie');
      });
    });

    group('deleteGroup', () {
      test('soft deletes a group by setting isActive to false', () async {
        await datasource.createGroup(testGroup);

        await datasource.deleteGroup('group_1');

        final stored = testBox.get('group_1');
        expect(stored, isNotNull);
        expect(stored['isActive'], false);
      });

      test('does nothing if group does not exist', () async {
        await datasource.deleteGroup('nonexistent_id');

        expect(testBox.length, 0);
      });

      test('preserves all other fields when soft deleting', () async {
        await datasource.createGroup(testGroup);

        await datasource.deleteGroup('group_1');

        final stored = testBox.get('group_1');
        expect(stored['id'], 'group_1');
        expect(stored['name'], 'Weekend Trip');
        expect(stored['memberIds'], ['user_1', 'user_2']);
        expect(stored['isActive'], false);
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

      test('persists member addition to storage', () async {
        await datasource.createGroup(testGroup);
        await datasource.addMember('group_1', 'user_3', 'Charlie');

        final stored = await datasource.getGroup('group_1');
        expect(stored!.memberIds, contains('user_3'));
        expect(stored.memberNames['user_3'], 'Charlie');
      });
    });

    group('removeMember', () {
      test('removes a member from a group', () async {
        await datasource.createGroup(testGroup);

        final updated = await datasource.removeMember('group_1', 'user_2');

        expect(updated.memberIds, isNot(contains('user_2')));
        expect(updated.memberNames.containsKey('user_2'), false);
        expect(updated.memberIds.length, 1);
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

      test('persists member removal to storage', () async {
        await datasource.createGroup(testGroup);
        await datasource.removeMember('group_1', 'user_2');

        final stored = await datasource.getGroup('group_1');
        expect(stored!.memberIds, isNot(contains('user_2')));
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

        expect(testBox.length, 3);
        expect(testBox.get('group_1'), isNotNull);
        expect(testBox.get('group_2'), isNotNull);
        expect(testBox.get('group_3'), isNotNull);
      });

      test('overwrites existing groups', () async {
        await datasource.createGroup(testGroup);

        final updated = testGroup.copyWith(name: 'Updated');
        await datasource.saveGroups([updated]);

        expect(testBox.length, 1);
        final stored = testBox.get('group_1');
        expect(stored['name'], 'Updated');
      });

      test('handles empty list', () async {
        await datasource.saveGroups([]);

        expect(testBox.length, 0);
      });
    });

    group('Edge Cases', () {
      test('handles concurrent operations', () async {
        final futures = List.generate(
          10,
          (i) => datasource.createGroup(
            testGroup.copyWith(id: 'group_$i', name: 'Group $i'),
          ),
        );

        await Future.wait(futures);

        expect(testBox.length, 10);
      });

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
