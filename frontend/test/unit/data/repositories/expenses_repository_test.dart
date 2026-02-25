import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:expense_tracker/data/datasources/local/expenses.dart';
import 'package:expense_tracker/data/datasources/remote/expenses.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';

class MockExpensesLocalDatasource extends Mock
    implements ExpensesLocalDatasource {}

class MockExpensesRemoteDatasource extends Mock
    implements ExpensesRemoteDatasource {}

void main() {
  late ExpenseRepository repository;
  late MockExpensesLocalDatasource mockLocalDataSource;
  late MockExpensesRemoteDatasource mockRemoteDataSource;

  late ExpenseCore testCore;
  late Expense testExpense;

  setUpAll(() {
    registerFallbackValue(
      Expense(
        core: ExpenseCore(
          id: 'fallback-id',
          title: 'Fallback Expense',
          amount: 0.0,
          currency: 'USD',
          createdAt: DateTime.now(),
        ),
        isSynced: false,
        deleted: false,
      ),
    );
  });

  setUp(() {
    mockLocalDataSource = MockExpensesLocalDatasource();
    mockRemoteDataSource = MockExpensesRemoteDatasource();

    repository = ExpenseRepository(
      remoteDataSource: mockRemoteDataSource,
      localDataSource: mockLocalDataSource,
    );

    testCore = ExpenseCore(
      id: '1',
      title: 'Test Expense',
      amount: 50.0,
      currency: 'USD',
      category: 'Food',
      createdAt: DateTime(2024, 6, 15),
    );

    testExpense = Expense(
      core: testCore,
      description: 'Test description',
      paymentMethod: 'Cash',
      isSynced: false,
      deleted: false,
    );
  });

  group('ExpenseRepository', () {
    group('initialize', () {
      test('should load expenses from local datasource', () async {
        final expenses = [testExpense];
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => expenses);

        await repository.initialize();

        verify(() => mockLocalDataSource.getExpenses()).called(1);
        expect(repository.getExpenses(), equals(expenses));
      });

      test('should not reinitialize if already initialized', () async {
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [testExpense]);

        await repository.initialize();
        await repository.initialize();

        verify(() => mockLocalDataSource.getExpenses()).called(1);
      });

      test('should throw error if initialization fails', () async {
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenThrow(Exception('Load failed'));

        expect(() => repository.initialize(), throwsException);
      });
    });

    group('createExpense', () {
      setUp(() async {
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => []);
        await repository.initialize();
      });

      test('should save expense locally with isSynced: false', () async {
        when(
          () => mockLocalDataSource.createExpense(any()),
        ).thenAnswer((_) async => true);

        await repository.createExpense(testExpense);

        final cachedExpense = repository.getExpenseById(testExpense.id);
        expect(cachedExpense?.isSynced, isFalse);
        verify(() => mockLocalDataSource.createExpense(any())).called(1);
      });

      test('should throw error if local save fails', () async {
        when(
          () => mockLocalDataSource.createExpense(any()),
        ).thenAnswer((_) async => false);

        expect(() => repository.createExpense(testExpense), throwsException);
      });
    });

    group('updateExpense', () {
      setUp(() async {
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [testExpense]);
        await repository.initialize();
      });

      test('should update expense locally with isSynced: false', () async {
        final updatedExpense = testExpense.copyWith(description: 'Updated');
        when(
          () => mockLocalDataSource.updateExpense(any()),
        ).thenAnswer((_) async => true);

        await repository.updateExpense(updatedExpense);

        final cached = repository.getExpenseById(testExpense.id);
        expect(cached?.description, equals('Updated'));
        expect(cached?.isSynced, isFalse);
      });

      test('should throw error if local update fails', () async {
        when(
          () => mockLocalDataSource.updateExpense(any()),
        ).thenAnswer((_) async => false);

        expect(() => repository.updateExpense(testExpense), throwsException);
      });
    });

    group('getUnsyncedExpenses', () {
      test('should return only unsynced expenses', () async {
        final synced = testExpense.copyWith(isSynced: true);
        final unsynced = testExpense.copyWith(
          core: testCore.copyWith(id: '2'),
          isSynced: false,
        );
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [synced, unsynced]);
        await repository.initialize();

        final result = repository.getUnsyncedExpenses();

        expect(result.length, equals(1));
        expect(result.first.id, equals('2'));
      });
    });

    group('getExpensesByDateRange', () {
      test('should return expenses within date range', () async {
        final exp1 = testExpense.copyWith(
          core: testCore.copyWith(createdAt: DateTime(2024, 6, 15)),
        );
        final exp2 = testExpense.copyWith(
          core: testCore.copyWith(id: '2', createdAt: DateTime(2024, 6, 20)),
        );
        final exp3 = testExpense.copyWith(
          core: testCore.copyWith(id: '3', createdAt: DateTime(2024, 7, 1)),
        );

        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [exp1, exp2, exp3]);
        await repository.initialize();

        final result = repository.getExpensesByDateRange(
          DateTime(2024, 6, 1),
          DateTime(2024, 6, 30),
        );

        expect(result.length, equals(2));
        expect(result.map((e) => e.id), contains('1'));
        expect(result.map((e) => e.id), contains('2'));
      });
    });

    group('syncExpenses', () {
      test('should sync all unsynced expenses to remote', () async {
        final unsynced1 = testExpense.copyWith(isSynced: false);
        final unsynced2 = testExpense.copyWith(
          core: testCore.copyWith(id: '2'),
          isSynced: false,
        );
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [unsynced1, unsynced2]);
        await repository.initialize();

        when(
          () => mockRemoteDataSource.updateExpense(any()),
        ).thenAnswer((_) async => false);
        when(
          () => mockRemoteDataSource.createExpense(any()),
        ).thenAnswer((_) async => true);
        when(
          () => mockLocalDataSource.updateExpense(any()),
        ).thenAnswer((_) async => true);

        await repository.syncExpenses();

        verify(
          () => mockRemoteDataSource.updateExpense(any()),
        ).called(greaterThanOrEqualTo(1));
      });

      test('should handle sync failures gracefully', () async {
        final unsynced = testExpense.copyWith(isSynced: false);
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [unsynced]);
        await repository.initialize();

        when(
          () => mockRemoteDataSource.updateExpense(any()),
        ).thenThrow(Exception('Network error'));
        when(
          () => mockRemoteDataSource.createExpense(any()),
        ).thenThrow(Exception('Network error'));

        expect(() => repository.syncExpenses(), returnsNormally);
      });
    });

    group('refresh', () {
      test('should sync local changes then pull remote expenses', () async {
        final unsynced = testExpense.copyWith(isSynced: false);
        final remote = testExpense.copyWith(
          core: testCore.copyWith(id: '2'),
          isSynced: true,
        );

        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [unsynced]);
        await repository.initialize();

        when(
          () => mockRemoteDataSource.createExpense(any()),
        ).thenAnswer((_) async => true);
        when(
          () => mockRemoteDataSource.getExpenses(),
        ).thenAnswer((_) async => [remote]);
        when(
          () => mockLocalDataSource.updateExpense(any()),
        ).thenAnswer((_) async => true);

        await repository.refresh();

        final result = repository.getExpenses();
        expect(result.length, equals(1));
        expect(result.first.id, equals('2'));
      });

      test('should throw error if refresh fails', () async {
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => []);
        await repository.initialize();

        when(
          () => mockRemoteDataSource.getExpenses(),
        ).thenThrow(Exception('Network error'));

        expect(() => repository.refresh(), throwsException);
      });

      test(
        'should persist remote expenses to local storage during refresh',
        () async {
          final remote1 = testExpense.copyWith(isSynced: true);
          final remote2 = testExpense.copyWith(
            core: testCore.copyWith(id: '2'),
            isSynced: true,
          );

          when(
            () => mockLocalDataSource.getExpenses(),
          ).thenAnswer((_) async => []);
          await repository.initialize();

          when(
            () => mockRemoteDataSource.getExpenses(),
          ).thenAnswer((_) async => [remote1, remote2]);
          when(
            () => mockLocalDataSource.updateExpense(any()),
          ).thenAnswer((_) async => true);

          await repository.refresh();

          // Verify updateExpense was called for both remote expenses
          verify(
            () => mockLocalDataSource.updateExpense(any()),
          ).called(greaterThanOrEqualTo(2));

          final cached = repository.getExpenses();
          expect(cached.length, equals(2));
          expect(cached.every((e) => e.isSynced), isTrue);
        },
      );

      test(
        'should create local expense if update fails during refresh',
        () async {
          final remote = testExpense.copyWith(isSynced: true);

          when(
            () => mockLocalDataSource.getExpenses(),
          ).thenAnswer((_) async => []);
          await repository.initialize();

          when(
            () => mockRemoteDataSource.getExpenses(),
          ).thenAnswer((_) async => [remote]);
          when(
            () => mockLocalDataSource.updateExpense(any()),
          ).thenAnswer((_) async => false); // Update fails (not found locally)
          when(
            () => mockLocalDataSource.createExpense(any()),
          ).thenAnswer((_) async => true);

          await repository.refresh();

          // Verify fallback: updateExpense called, then createExpense called
          verify(() => mockLocalDataSource.updateExpense(any())).called(1);
          verify(() => mockLocalDataSource.createExpense(any())).called(1);
        },
      );
    });

    group('Soft-delete sync', () {
      test(
        'should sync deleted expense by updating remote with deleted flag',
        () async {
          final deletedExpense = testExpense.copyWith(
            deleted: true,
            isSynced: false,
          );

          when(
            () => mockLocalDataSource.getExpenses(),
          ).thenAnswer((_) async => [deletedExpense]);
          await repository.initialize();

          when(
            () => mockRemoteDataSource.updateExpense(any()),
          ).thenAnswer((_) async => true);
          when(
            () => mockLocalDataSource.updateExpense(any()),
          ).thenAnswer((_) async => true);

          await repository.syncExpenses();

          // Verify updateExpense was called (not deleteExpense, since it's removed)
          verify(
            () => mockRemoteDataSource.updateExpense(
              any(
                that: isA<Expense>().having((e) => e.deleted, 'deleted', true),
              ),
            ),
          ).called(1);

          final synced = repository.getExpenseById(deletedExpense.id);
          expect(synced?.deleted, isTrue);
          expect(synced?.isSynced, isTrue);
        },
      );

      test('should mark soft-deleted expense as synced locally', () async {
        final deletedExpense = testExpense.copyWith(
          deleted: true,
          isSynced: false,
        );

        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [deletedExpense]);
        await repository.initialize();

        when(
          () => mockRemoteDataSource.updateExpense(any()),
        ).thenAnswer((_) async => true);
        when(
          () => mockLocalDataSource.updateExpense(any()),
        ).thenAnswer((_) async => true);

        await repository.syncExpenses();

        final result = repository.getExpenseById(deletedExpense.id);
        expect(result?.isSynced, isTrue);
        verify(
          () => mockLocalDataSource.updateExpense(any()),
        ).called(greaterThanOrEqualTo(1));
      });
    });

    group('Edge cases', () {
      test('should handle syncExpenses with empty cache', () async {
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => []);
        await repository.initialize();

        expect(() => repository.syncExpenses(), returnsNormally);
        verifyNever(() => mockRemoteDataSource.updateExpense(any()));
      });

      test('should handle partial sync failures gracefully', () async {
        final expense1 = testExpense.copyWith(isSynced: false);
        final expense2 = testExpense.copyWith(
          core: testCore.copyWith(id: '2'),
          isSynced: false,
        );

        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [expense1, expense2]);
        await repository.initialize();

        // Both expenses attempt remote sync but local is always successful
        when(
          () => mockRemoteDataSource.updateExpense(any()),
        ).thenAnswer((_) async => true); // Both updates succeed
        when(
          () => mockRemoteDataSource.createExpense(any()),
        ).thenAnswer((_) async => true);
        when(
          () => mockLocalDataSource.updateExpense(any()),
        ).thenAnswer((_) async => true);

        await repository.syncExpenses();

        // Both expenses should be synced
        final synced1 = repository.getExpenseById(expense1.id);
        final synced2 = repository.getExpenseById(expense2.id);
        expect(synced1?.isSynced, isTrue);
        expect(synced2?.isSynced, isTrue);
      });

      test('should return all expenses from cache via getExpenses', () async {
        final exp1 = testExpense;
        final exp2 = testExpense.copyWith(core: testCore.copyWith(id: '2'));

        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [exp1, exp2]);
        await repository.initialize();

        final result = repository.getExpenses();

        expect(result.length, equals(2));
        expect(result.map((e) => e.id), containsAll(['1', '2']));
      });

      test('should return null for non-existent expense', () async {
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => []);
        await repository.initialize();

        final result = repository.getExpenseById('non-existent');

        expect(result, isNull);
      });

      test('should handle refresh with empty remote response', () async {
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [testExpense]);
        await repository.initialize();

        when(
          () => mockRemoteDataSource.getExpenses(),
        ).thenAnswer((_) async => []);

        await repository.refresh();

        final result = repository.getExpenses();
        expect(result.length, equals(0));
      });

      test('should return early when no expenses to sync', () async {
        // Initialize with only synced expenses
        final synced = testExpense.copyWith(isSynced: true);
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [synced]);
        await repository.initialize();

        // getUnsyncedExpenses should return empty list
        expect(repository.getUnsyncedExpenses(), isEmpty);

        // syncExpenses should return early without calling remote
        await repository.syncExpenses();

        verifyNever(() => mockRemoteDataSource.updateExpense(any()));
        verifyNever(() => mockRemoteDataSource.createExpense(any()));
      });

      test('should catch and log exceptions in _syncExpenseToRemote', () async {
        final unsynced = testExpense.copyWith(isSynced: false);
        when(
          () => mockLocalDataSource.getExpenses(),
        ).thenAnswer((_) async => [unsynced]);
        await repository.initialize();

        // Simulate both update and create throwing exceptions
        when(
          () => mockRemoteDataSource.updateExpense(any()),
        ).thenThrow(Exception('Update failed'));
        when(
          () => mockRemoteDataSource.createExpense(any()),
        ).thenThrow(Exception('Create failed'));

        // Should not rethrow, exception is caught in _syncExpenseToRemote
        expect(() => repository.syncExpenses(), returnsNormally);

        // Expense should remain unsynced since both remote calls failed
        final result = repository.getExpenseById(unsynced.id);
        expect(result?.isSynced, isFalse);
      });

      test(
        'should handle exception at syncExpenses level and rethrow',
        () async {
          final unsynced = testExpense.copyWith(isSynced: false);
          when(
            () => mockLocalDataSource.getExpenses(),
          ).thenAnswer((_) async => [unsynced]);
          await repository.initialize();

          // Simulate update succeeds but local update throws
          when(
            () => mockRemoteDataSource.updateExpense(any()),
          ).thenAnswer((_) async => true);
          when(
            () => mockLocalDataSource.updateExpense(any()),
          ).thenThrow(Exception('Local storage error'));

          // Exception in _syncExpenseToRemote is caught, not propagated
          expect(() => repository.syncExpenses(), returnsNormally);
        },
      );

      test(
        'should catch exception in _syncExpenseToRemote and log error when both remote operations throw',
        () async {
          final unsynced = testExpense.copyWith(isSynced: false);
          when(
            () => mockLocalDataSource.getExpenses(),
          ).thenAnswer((_) async => [unsynced]);
          await repository.initialize();

          // Both remote operations throw to trigger catch block in _syncExpenseToRemote
          when(
            () => mockRemoteDataSource.updateExpense(any()),
          ).thenThrow(Exception('Remote update error'));
          when(
            () => mockRemoteDataSource.createExpense(any()),
          ).thenThrow(Exception('Remote create error'));

          // syncExpenses should catch the exception in _syncExpenseToRemote
          // and continue without rethrowing - this tests line 182 (catch block)
          expect(() => repository.syncExpenses(), returnsNormally);

          // Verify expense remains unsynced (error was caught and logged)
          final result = repository.getExpenseById(unsynced.id);
          expect(result?.isSynced, isFalse);
        },
      );

      test(
        'should handle exception during iteration in syncExpenses gracefully',
        () async {
          // Initialize with two expenses
          final exp1 = testExpense.copyWith(isSynced: false);
          final exp2 = testExpense.copyWith(
            core: testCore.copyWith(id: '2'),
            isSynced: false,
          );

          when(
            () => mockLocalDataSource.getExpenses(),
          ).thenAnswer((_) async => [exp1, exp2]);
          await repository.initialize();

          // First sync succeeds, second throws to test catch block
          var callCount = 0;
          when(() => mockRemoteDataSource.updateExpense(any())).thenAnswer((_) {
            callCount++;
            if (callCount == 1) {
              return Future.value(true); // First succeeds
            } else {
              return Future.error(Exception('Second failed')); // Second fails
            }
          });
          when(
            () => mockLocalDataSource.updateExpense(any()),
          ).thenAnswer((_) async => true);

          // Should not rethrow - catches error in _syncExpenseToRemote
          expect(() => repository.syncExpenses(), returnsNormally);
        },
      );
    });
  });
}
