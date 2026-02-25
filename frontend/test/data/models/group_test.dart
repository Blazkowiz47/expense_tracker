import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/data/models/group.dart';

void main() {
  group('Group Model', () {
    final testDate = DateTime(2024, 1, 15, 10, 30);

    final testGroup = Group(
      id: 'group_123',
      name: 'Weekend Trip',
      creatorId: 'user_1',
      memberIds: ['user_1', 'user_2', 'user_3'],
      memberNames: {'user_1': 'Alice', 'user_2': 'Bob', 'user_3': 'Charlie'},
      createdAt: testDate,
      isActive: true,
    );

    group('Constructor', () {
      test('creates instance with all fields', () {
        expect(testGroup.id, 'group_123');
        expect(testGroup.name, 'Weekend Trip');
        expect(testGroup.creatorId, 'user_1');
        expect(testGroup.memberIds, ['user_1', 'user_2', 'user_3']);
        expect(testGroup.memberNames['user_1'], 'Alice');
        expect(testGroup.memberNames['user_2'], 'Bob');
        expect(testGroup.memberNames['user_3'], 'Charlie');
        expect(testGroup.createdAt, testDate);
        expect(testGroup.isActive, true);
      });

      test('memberIds and memberNames are independent lists', () {
        final group = Group(
          id: 'group_1',
          name: 'Test',
          creatorId: 'user_1',
          memberIds: ['user_1', 'user_2'],
          memberNames: {'user_1': 'Alice'},
          createdAt: testDate,
          isActive: true,
        );

        expect(group.memberIds.length, 2);
        expect(group.memberNames.length, 1);
      });
    });

    group('JSON Serialization', () {
      test('toJson converts Group to JSON map', () {
        final json = testGroup.toJson();

        expect(json['id'], 'group_123');
        expect(json['name'], 'Weekend Trip');
        expect(json['creatorId'], 'user_1');
        expect(json['memberIds'], ['user_1', 'user_2', 'user_3']);
        expect(json['memberNames'], {
          'user_1': 'Alice',
          'user_2': 'Bob',
          'user_3': 'Charlie',
        });
        expect(json['createdAt'], testDate.toIso8601String());
        expect(json['isActive'], true);
      });

      test('fromJson creates Group from JSON map', () {
        final json = {
          'id': 'group_456',
          'name': 'Dinner Party',
          'creatorId': 'user_2',
          'memberIds': ['user_2', 'user_4'],
          'memberNames': {'user_2': 'Bob', 'user_4': 'Diana'},
          'createdAt': testDate.toIso8601String(),
          'isActive': false,
        };

        final group = Group.fromJson(json);

        expect(group.id, 'group_456');
        expect(group.name, 'Dinner Party');
        expect(group.creatorId, 'user_2');
        expect(group.memberIds, ['user_2', 'user_4']);
        expect(group.memberNames['user_2'], 'Bob');
        expect(group.memberNames['user_4'], 'Diana');
        expect(group.createdAt, testDate);
        expect(group.isActive, false);
      });

      test('roundtrip serialization maintains data integrity', () {
        final json = testGroup.toJson();
        final reconstructed = Group.fromJson(json);

        expect(reconstructed, testGroup);
      });

      test('handles empty memberIds and memberNames', () {
        final group = Group(
          id: 'group_empty',
          name: 'Empty Group',
          creatorId: 'user_1',
          memberIds: [],
          memberNames: {},
          createdAt: testDate,
          isActive: true,
        );

        final json = group.toJson();
        final reconstructed = Group.fromJson(json);

        expect(reconstructed.memberIds, isEmpty);
        expect(reconstructed.memberNames, isEmpty);
      });
    });

    group('Equatable', () {
      test('two groups with same data are equal', () {
        final group1 = Group(
          id: 'group_1',
          name: 'Test',
          creatorId: 'user_1',
          memberIds: ['user_1', 'user_2'],
          memberNames: {'user_1': 'Alice', 'user_2': 'Bob'},
          createdAt: testDate,
          isActive: true,
        );

        final group2 = Group(
          id: 'group_1',
          name: 'Test',
          creatorId: 'user_1',
          memberIds: ['user_1', 'user_2'],
          memberNames: {'user_1': 'Alice', 'user_2': 'Bob'},
          createdAt: testDate,
          isActive: true,
        );

        expect(group1, group2);
        expect(group1.hashCode, group2.hashCode);
      });

      test('two groups with different ids are not equal', () {
        final group1 = testGroup;
        final group2 = testGroup.copyWith(id: 'different_id');

        expect(group1, isNot(group2));
      });

      test('two groups with different memberIds are not equal', () {
        final group1 = testGroup;
        final group2 = testGroup.copyWith(memberIds: ['user_1', 'user_2']);

        expect(group1, isNot(group2));
      });

      test('two groups with different memberNames are not equal', () {
        final group1 = testGroup;
        final group2 = testGroup.copyWith(
          memberNames: {'user_1': 'Alice', 'user_2': 'Robert'},
        );

        expect(group1, isNot(group2));
      });
    });

    group('copyWith', () {
      test('copies with no changes returns equal instance', () {
        final copied = testGroup.copyWith();
        expect(copied, testGroup);
      });

      test('copies with new name', () {
        final copied = testGroup.copyWith(name: 'Updated Trip');
        expect(copied.name, 'Updated Trip');
        expect(copied.id, testGroup.id);
        expect(copied.memberIds, testGroup.memberIds);
      });

      test('copies with new memberIds', () {
        final newMemberIds = ['user_1', 'user_2', 'user_3', 'user_4'];
        final copied = testGroup.copyWith(memberIds: newMemberIds);
        expect(copied.memberIds, newMemberIds);
        expect(copied.name, testGroup.name);
      });

      test('copies with new memberNames', () {
        final newMemberNames = {
          'user_1': 'Alice',
          'user_2': 'Bobby',
          'user_3': 'Chuck',
        };
        final copied = testGroup.copyWith(memberNames: newMemberNames);
        expect(copied.memberNames, newMemberNames);
        expect(copied.id, testGroup.id);
      });

      test('copies with new isActive', () {
        final copied = testGroup.copyWith(isActive: false);
        expect(copied.isActive, false);
        expect(copied.id, testGroup.id);
      });

      test('copies with multiple fields', () {
        final copied = testGroup.copyWith(
          name: 'New Trip',
          isActive: false,
          memberIds: ['user_1'],
        );
        expect(copied.name, 'New Trip');
        expect(copied.isActive, false);
        expect(copied.memberIds, ['user_1']);
        expect(copied.creatorId, testGroup.creatorId);
      });
    });

    group('toString', () {
      test('returns formatted string representation', () {
        final str = testGroup.toString();
        expect(str, contains('Group'));
        expect(str, contains('id: group_123'));
        expect(str, contains('name: Weekend Trip'));
        expect(str, contains('creatorId: user_1'));
      });
    });

    group('Edge Cases', () {
      test('handles single member group', () {
        final group = Group(
          id: 'group_solo',
          name: 'Solo',
          creatorId: 'user_1',
          memberIds: ['user_1'],
          memberNames: {'user_1': 'Alice'},
          createdAt: testDate,
          isActive: true,
        );

        expect(group.memberIds.length, 1);
        expect(group.memberNames.length, 1);
      });

      test('handles very long group name', () {
        final longName = 'A' * 500;
        final group = Group(
          id: 'group_long',
          name: longName,
          creatorId: 'user_1',
          memberIds: ['user_1'],
          memberNames: {'user_1': 'Alice'},
          createdAt: testDate,
          isActive: true,
        );

        expect(group.name.length, 500);
        final json = group.toJson();
        final reconstructed = Group.fromJson(json);
        expect(reconstructed.name, longName);
      });

      test('handles many members', () {
        final memberIds = List.generate(100, (i) => 'user_$i');
        final memberNames = Map.fromEntries(
          List.generate(100, (i) => MapEntry('user_$i', 'User $i')),
        );

        final group = Group(
          id: 'group_large',
          name: 'Large Group',
          creatorId: 'user_0',
          memberIds: memberIds,
          memberNames: memberNames,
          createdAt: testDate,
          isActive: true,
        );

        expect(group.memberIds.length, 100);
        expect(group.memberNames.length, 100);

        final json = group.toJson();
        final reconstructed = Group.fromJson(json);
        expect(reconstructed.memberIds.length, 100);
        expect(reconstructed.memberNames.length, 100);
      });

      test('handles special characters in names', () {
        final group = Group(
          id: 'group_special',
          name: 'Trip 🌍 2024! @#\$%',
          creatorId: 'user_1',
          memberIds: ['user_1', 'user_2'],
          memberNames: {'user_1': 'Café ☕', 'user_2': 'José María'},
          createdAt: testDate,
          isActive: true,
        );

        final json = group.toJson();
        final reconstructed = Group.fromJson(json);
        expect(reconstructed.name, 'Trip 🌍 2024! @#\$%');
        expect(reconstructed.memberNames['user_1'], 'Café ☕');
        expect(reconstructed.memberNames['user_2'], 'José María');
      });
    });
  });
}
