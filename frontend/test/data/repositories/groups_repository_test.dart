import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:expense_tracker/data/repositories/groups_repository.dart';
import 'package:expense_tracker/data/datasources/groups.dart';
import 'package:expense_tracker/data/models/group.dart';

class MockLocalDatasource extends Mock implements GroupsDatasource {}

class MockRemoteDatasource extends Mock implements GroupsDatasource {}

void main() {
  late GroupsRepository repository;
  late MockLocalDatasource mockLocal;
  late MockRemoteDatasource mockRemote;

  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(
      Group(
        id: 'fallback',
        name: 'Fallback',
        creatorId: 'user_1',
        memberIds: [],
        memberNames: {},
        createdAt: DateTime.now(),
        isActive: true,
      ),
    );
  });

  setUp(() {
    mockLocal = MockLocalDatasource();
    mockRemote = MockRemoteDatasource();
    repository = GroupsRepository(
      localDatasource: mockLocal,
      remoteDatasource: mockRemote,
    );

    // Default stubs
    when(() => mockLocal.initialize()).thenAnswer((_) async {});
    when(() => mockLocal.close()).thenAnswer((_) async {});
    when(() => mockRemote.initialize()).thenAnswer((_) async {});
    when(() => mockRemote.close()).thenAnswer((_) async {});
    when(() => mockLocal.getAllGroups()).thenAnswer((_) async => []);
  });

  group('GroupsRepository', () {
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

    group('initialize', () {
      test('initializes both datasources', () async {
        await repository.initialize();

        verify(() => mockLocal.initialize()).called(1);
        verify(() => mockRemote.initialize()).called(1);
      });

      test('loads groups from local datasource into cache', () async {
        when(
          () => mockLocal.getAllGroups(),
        ).thenAnswer((_) async => [testGroup]);

        await repository.initialize();

        final groups = repository.getGroupsFromCache();
        expect(groups.length, 1);
        expect(groups.first.id, 'group_1');
      });

      test('handles empty local datasource', () async {
        when(() => mockLocal.getAllGroups()).thenAnswer((_) async => []);

        await repository.initialize();

        final groups = repository.getGroupsFromCache();
        expect(groups, isEmpty);
      });
    });

    group('close', () {
      test('closes both datasources', () async {
        await repository.close();

        verify(() => mockLocal.close()).called(1);
        verify(() => mockRemote.close()).called(1);
      });
    });

    group('createGroup', () {
      test('creates group in both local and remote datasources', () async {
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        when(
          () => mockRemote.createGroup(any()),
        ).thenAnswer((_) async => testGroup);

        final created = await repository.createGroup(testGroup);

        expect(created, testGroup);
        verify(() => mockLocal.createGroup(testGroup)).called(1);
        verify(() => mockRemote.createGroup(testGroup)).called(1);
      });

      test('adds group to in-memory cache', () async {
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        when(
          () => mockRemote.createGroup(any()),
        ).thenAnswer((_) async => testGroup);

        await repository.createGroup(testGroup);

        final groups = repository.getGroupsFromCache();
        expect(groups.any((g) => g.id == 'group_1'), true);
      });

      test('updates cache if group already exists', () async {
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        when(
          () => mockRemote.createGroup(any()),
        ).thenAnswer((_) async => testGroup);

        await repository.createGroup(testGroup);

        final updated = testGroup.copyWith(name: 'Updated');
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => updated);
        when(
          () => mockRemote.createGroup(any()),
        ).thenAnswer((_) async => updated);

        await repository.createGroup(updated);

        final groups = repository.getGroupsFromCache();
        expect(groups.length, 1);
        expect(groups.first.name, 'Updated');
      });

      test('saves to local even if remote fails', () async {
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        when(
          () => mockRemote.createGroup(any()),
        ).thenThrow(Exception('Network error'));

        await repository.createGroup(testGroup);

        verify(() => mockLocal.createGroup(testGroup)).called(1);
        final groups = repository.getGroupsFromCache();
        expect(groups.any((g) => g.id == 'group_1'), true);
      });
    });

    group('updateGroup', () {
      test('updates group in both datasources', () async {
        when(
          () => mockLocal.updateGroup(any()),
        ).thenAnswer((_) async => testGroup);
        when(
          () => mockRemote.updateGroup(any()),
        ).thenAnswer((_) async => testGroup);

        final updated = await repository.updateGroup(testGroup);

        expect(updated, testGroup);
        verify(() => mockLocal.updateGroup(testGroup)).called(1);
        verify(() => mockRemote.updateGroup(testGroup)).called(1);
      });

      test('updates group in cache', () async {
        // First create the group
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        when(
          () => mockRemote.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        await repository.createGroup(testGroup);

        // Then update it
        final updated = testGroup.copyWith(name: 'Updated Trip');
        when(
          () => mockLocal.updateGroup(any()),
        ).thenAnswer((_) async => updated);
        when(
          () => mockRemote.updateGroup(any()),
        ).thenAnswer((_) async => updated);

        await repository.updateGroup(updated);

        final groups = repository.getGroupsFromCache();
        expect(groups.first.name, 'Updated Trip');
      });
    });

    group('deleteGroup', () {
      test('soft deletes group in both datasources', () async {
        when(() => mockLocal.deleteGroup(any())).thenAnswer((_) async {});
        when(() => mockRemote.deleteGroup(any())).thenAnswer((_) async {});

        await repository.deleteGroup('group_1');

        verify(() => mockLocal.deleteGroup('group_1')).called(1);
        verify(() => mockRemote.deleteGroup('group_1')).called(1);
      });

      test('marks group as inactive in cache', () async {
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        when(
          () => mockRemote.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        await repository.createGroup(testGroup);

        when(() => mockLocal.deleteGroup(any())).thenAnswer((_) async {});
        when(() => mockRemote.deleteGroup(any())).thenAnswer((_) async {});

        await repository.deleteGroup('group_1');

        final groups = repository.getGroupsFromCache();
        expect(groups.first.isActive, false);
      });
    });

    group('getGroup', () {
      test('returns group from cache if available', () async {
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        when(
          () => mockRemote.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        await repository.createGroup(testGroup);

        final result = repository.getGroup('group_1');

        expect(result, isNotNull);
        expect(result!.id, 'group_1');
        verifyNever(() => mockLocal.getGroup(any()));
      });

      test('returns null if group not in cache', () {
        final result = repository.getGroup('nonexistent_id');

        expect(result, isNull);
      });
    });

    group('getUserGroups', () {
      test('returns active groups where user is member', () async {
        final group1 = testGroup;
        final group2 = Group(
          id: 'group_2',
          name: 'Dinner',
          creatorId: 'user_2',
          memberIds: ['user_2', 'user_3'],
          memberNames: {'user_2': 'Bob', 'user_3': 'Charlie'},
          createdAt: testDate,
          isActive: true,
        );
        final group3 = Group(
          id: 'group_3',
          name: 'Lunch',
          creatorId: 'user_1',
          memberIds: ['user_1', 'user_3'],
          memberNames: {'user_1': 'Alice', 'user_3': 'Charlie'},
          createdAt: testDate,
          isActive: true,
        );

        when(() => mockLocal.createGroup(any())).thenAnswer(
          (invocation) async => invocation.positionalArguments[0] as Group,
        );
        when(() => mockRemote.createGroup(any())).thenAnswer(
          (invocation) async => invocation.positionalArguments[0] as Group,
        );

        await repository.createGroup(group1);
        await repository.createGroup(group2);
        await repository.createGroup(group3);

        final user1Groups = repository.getUserGroups('user_1');

        expect(user1Groups.length, 2);
        expect(user1Groups.any((g) => g.id == 'group_1'), true);
        expect(user1Groups.any((g) => g.id == 'group_3'), true);
      });

      test('filters out inactive groups', () async {
        final group1 = testGroup;
        final group2 = testGroup.copyWith(id: 'group_2', isActive: false);

        when(() => mockLocal.createGroup(any())).thenAnswer(
          (invocation) async => invocation.positionalArguments[0] as Group,
        );
        when(() => mockRemote.createGroup(any())).thenAnswer(
          (invocation) async => invocation.positionalArguments[0] as Group,
        );

        await repository.createGroup(group1);
        await repository.createGroup(group2);

        final user1Groups = repository.getUserGroups('user_1');

        expect(user1Groups.length, 1);
        expect(user1Groups.first.id, 'group_1');
      });

      test('returns empty list if user not in any groups', () {
        final result = repository.getUserGroups('user_99');

        expect(result, isEmpty);
      });
    });

    group('addMember', () {
      test('adds member to group in both datasources', () async {
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        when(
          () => mockRemote.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        await repository.createGroup(testGroup);

        final updatedGroup = testGroup.copyWith(
          memberIds: ['user_1', 'user_2', 'user_3'],
          memberNames: {
            'user_1': 'Alice',
            'user_2': 'Bob',
            'user_3': 'Charlie',
          },
        );

        when(
          () => mockLocal.addMember(any(), any(), any()),
        ).thenAnswer((_) async => updatedGroup);
        when(
          () => mockRemote.addMember(any(), any(), any()),
        ).thenAnswer((_) async => updatedGroup);

        final result = await repository.addMember(
          'group_1',
          'user_3',
          'Charlie',
        );

        expect(result.memberIds.length, 3);
        verify(
          () => mockLocal.addMember('group_1', 'user_3', 'Charlie'),
        ).called(1);
        verify(
          () => mockRemote.addMember('group_1', 'user_3', 'Charlie'),
        ).called(1);
      });

      test('updates cache with new member', () async {
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        when(
          () => mockRemote.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        await repository.createGroup(testGroup);

        final updatedGroup = testGroup.copyWith(
          memberIds: ['user_1', 'user_2', 'user_3'],
          memberNames: {
            'user_1': 'Alice',
            'user_2': 'Bob',
            'user_3': 'Charlie',
          },
        );

        when(
          () => mockLocal.addMember(any(), any(), any()),
        ).thenAnswer((_) async => updatedGroup);
        when(
          () => mockRemote.addMember(any(), any(), any()),
        ).thenAnswer((_) async => updatedGroup);

        await repository.addMember('group_1', 'user_3', 'Charlie');

        final cached = repository.getGroup('group_1');
        expect(cached!.memberIds, contains('user_3'));
      });
    });

    group('removeMember', () {
      test('removes member from group in both datasources', () async {
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        when(
          () => mockRemote.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        await repository.createGroup(testGroup);

        final updatedGroup = testGroup.copyWith(
          memberIds: ['user_1'],
          memberNames: {'user_1': 'Alice'},
        );

        when(
          () => mockLocal.removeMember(any(), any()),
        ).thenAnswer((_) async => updatedGroup);
        when(
          () => mockRemote.removeMember(any(), any()),
        ).thenAnswer((_) async => updatedGroup);

        final result = await repository.removeMember('group_1', 'user_2');

        expect(result.memberIds.length, 1);
        verify(() => mockLocal.removeMember('group_1', 'user_2')).called(1);
        verify(() => mockRemote.removeMember('group_1', 'user_2')).called(1);
      });

      test('updates cache after removing member', () async {
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        when(
          () => mockRemote.createGroup(any()),
        ).thenAnswer((_) async => testGroup);
        await repository.createGroup(testGroup);

        final updatedGroup = testGroup.copyWith(
          memberIds: ['user_1'],
          memberNames: {'user_1': 'Alice'},
        );

        when(
          () => mockLocal.removeMember(any(), any()),
        ).thenAnswer((_) async => updatedGroup);
        when(
          () => mockRemote.removeMember(any(), any()),
        ).thenAnswer((_) async => updatedGroup);

        await repository.removeMember('group_1', 'user_2');

        final cached = repository.getGroup('group_1');
        expect(cached!.memberIds, isNot(contains('user_2')));
      });
    });

    group('syncGroups', () {
      test('syncs groups from remote to local for user', () async {
        when(
          () => mockRemote.getGroupsByUser(any()),
        ).thenAnswer((_) async => [testGroup]);
        when(() => mockLocal.saveGroups(any())).thenAnswer((_) async {});

        await repository.syncGroups('user_1');

        verify(() => mockRemote.getGroupsByUser('user_1')).called(1);
        verify(() => mockLocal.saveGroups([testGroup])).called(1);
      });

      test('updates cache with synced groups', () async {
        when(
          () => mockRemote.getGroupsByUser(any()),
        ).thenAnswer((_) async => [testGroup]);
        when(() => mockLocal.saveGroups(any())).thenAnswer((_) async {});

        await repository.syncGroups('user_1');

        final groups = repository.getGroupsFromCache();
        expect(groups.length, 1);
        expect(groups.first.id, 'group_1');
      });

      test('merges synced groups with existing cache', () async {
        // Add initial group to cache
        final group1 = testGroup;
        when(
          () => mockLocal.createGroup(any()),
        ).thenAnswer((_) async => group1);
        when(
          () => mockRemote.createGroup(any()),
        ).thenAnswer((_) async => group1);
        await repository.createGroup(group1);

        // Sync new group
        final group2 = testGroup.copyWith(id: 'group_2', name: 'Dinner');
        when(
          () => mockRemote.getGroupsByUser(any()),
        ).thenAnswer((_) async => [group2]);
        when(() => mockLocal.saveGroups(any())).thenAnswer((_) async {});

        await repository.syncGroups('user_1');

        final groups = repository.getGroupsFromCache();
        expect(groups.length, 2);
      });

      test('handles sync errors gracefully', () async {
        when(
          () => mockRemote.getGroupsByUser(any()),
        ).thenThrow(Exception('Network error'));

        expect(() => repository.syncGroups('user_1'), throwsException);
      });
    });

    group('getGroupsFromCache', () {
      test('returns all groups from cache', () async {
        final group1 = testGroup;
        final group2 = testGroup.copyWith(id: 'group_2', name: 'Dinner');

        when(() => mockLocal.createGroup(any())).thenAnswer(
          (invocation) async => invocation.positionalArguments[0] as Group,
        );
        when(() => mockRemote.createGroup(any())).thenAnswer(
          (invocation) async => invocation.positionalArguments[0] as Group,
        );

        await repository.createGroup(group1);
        await repository.createGroup(group2);

        final all = repository.getGroupsFromCache();

        expect(all.length, 2);
        expect(all.any((g) => g.id == 'group_1'), true);
        expect(all.any((g) => g.id == 'group_2'), true);
      });

      test('returns empty list if cache is empty', () {
        final all = repository.getGroupsFromCache();

        expect(all, isEmpty);
      });
    });
  });
}
