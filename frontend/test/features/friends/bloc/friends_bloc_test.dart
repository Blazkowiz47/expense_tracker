import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/friends/bloc/friends_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockExpensesBloc extends Mock implements ExpensesBloc {}

void main() {
  late MockExpensesBloc mockExpensesBloc;
  late FriendsBloc bloc;
  late StreamController<ExpensesState> expensesStateController;

  final testExpense1 = Expense(
    core: ExpenseCore(
      id: 'expense1',
      title: 'Lunch with Alice',
      amount: 100.0,
      currency: 'USD',
      category: 'Food',
      createdAt: DateTime(2025, 1, 1),
    ),
    description: 'Shared with Alice',
  );

  final testExpense2 = Expense(
    core: ExpenseCore(
      id: 'expense2',
      title: 'Dinner with Bob',
      amount: 200.0,
      currency: 'USD',
      category: 'Food',
      createdAt: DateTime(2025, 1, 2),
    ),
    description: 'Split with Bob',
  );

  final testExpense3 = Expense(
    core: ExpenseCore(
      id: 'expense3',
      title: 'Coffee with Alice',
      amount: 50.0,
      currency: 'USD',
      category: 'Food',
      createdAt: DateTime(2025, 1, 3),
    ),
    description: 'Coffee break with Alice',
  );

  setUp(() {
    mockExpensesBloc = MockExpensesBloc();
    expensesStateController = StreamController<ExpensesState>.broadcast();

    when(
      () => mockExpensesBloc.stream,
    ).thenAnswer((_) => expensesStateController.stream);
    when(() => mockExpensesBloc.state).thenReturn(const ExpensesInitial());

    bloc = FriendsBloc(expensesBloc: mockExpensesBloc);
  });

  tearDown(() {
    bloc.close();
    expensesStateController.close();
  });

  group('FriendsBloc', () {
    test('initial state is FriendsInitial', () {
      expect(bloc.state, equals(const FriendsInitial()));
    });

    group('LoadFriends', () {
      blocTest<FriendsBloc, FriendsState>(
        'emits [Loading, Loaded] when friends are derived from expenses',
        build: () {
          when(() => mockExpensesBloc.state).thenReturn(
            ExpensesLoaded(
              expenses: [testExpense1, testExpense2, testExpense3],
            ),
          );
          return bloc;
        },
        act: (bloc) => bloc.add(const LoadFriends()),
        expect: () => [
          const FriendsLoading(),
          isA<FriendsLoaded>()
              .having((s) => s.friends.length, 'friends count', 2)
              .having(
                (s) => s.friends.any((f) => f.name == 'Alice'),
                'has Alice',
                true,
              )
              .having(
                (s) => s.friends.any((f) => f.name == 'Bob'),
                'has Bob',
                true,
              ),
        ],
      );

      blocTest<FriendsBloc, FriendsState>(
        'calculates correct expense count and total for each friend',
        build: () {
          when(() => mockExpensesBloc.state).thenReturn(
            ExpensesLoaded(
              expenses: [testExpense1, testExpense2, testExpense3],
            ),
          );
          return bloc;
        },
        act: (bloc) => bloc.add(const LoadFriends()),
        verify: (_) {
          final state = bloc.state as FriendsLoaded;
          final alice = state.friends.firstWhere((f) => f.name == 'Alice');
          final bob = state.friends.firstWhere((f) => f.name == 'Bob');

          expect(alice.expenseCount, 2); // expense1 and expense3
          expect(alice.totalAmount, 150.0); // 100 + 50
          expect(bob.expenseCount, 1); // expense2
          expect(bob.totalAmount, 200.0);
        },
      );

      blocTest<FriendsBloc, FriendsState>(
        'emits [Loading, Loaded] with empty list when no friends found',
        build: () {
          final expenseWithoutFriends = Expense(
            core: ExpenseCore(
              id: 'expense4',
              title: 'Solo lunch',
              amount: 50.0,
              currency: 'USD',
              category: 'Food',
              createdAt: DateTime(2025, 1, 4),
            ),
            description: 'Just me',
          );
          when(
            () => mockExpensesBloc.state,
          ).thenReturn(ExpensesLoaded(expenses: [expenseWithoutFriends]));
          return bloc;
        },
        act: (bloc) => bloc.add(const LoadFriends()),
        expect: () => [
          const FriendsLoading(),
          const FriendsLoaded(friends: []),
        ],
      );

      blocTest<FriendsBloc, FriendsState>(
        'emits [Loading, Error] when ExpensesBloc is not in Loaded state',
        build: () {
          when(
            () => mockExpensesBloc.state,
          ).thenReturn(const ExpensesLoading());
          return bloc;
        },
        act: (bloc) => bloc.add(const LoadFriends()),
        expect: () => [
          const FriendsLoading(),
          const FriendsError(
            message: 'Expenses not loaded. Cannot derive friends.',
          ),
        ],
      );
    });

    group('UpdateFriends (on ExpensesBloc stream)', () {
      blocTest<FriendsBloc, FriendsState>(
        'automatically updates friends when ExpensesBloc emits ExpensesLoaded',
        build: () => bloc,
        act: (bloc) async {
          // Simulate ExpensesBloc emitting ExpensesLoaded
          expensesStateController.add(
            ExpensesLoaded(expenses: [testExpense1, testExpense2]),
          );
          await Future.delayed(const Duration(milliseconds: 100));
        },
        expect: () => [
          const FriendsLoading(),
          isA<FriendsLoaded>().having(
            (s) => s.friends.length,
            'friends count',
            2,
          ),
        ],
      );

      blocTest<FriendsBloc, FriendsState>(
        'updates friends when expenses change',
        build: () => bloc,
        act: (bloc) async {
          // First emit with 2 expenses
          expensesStateController.add(
            ExpensesLoaded(expenses: [testExpense1, testExpense2]),
          );
          await Future.delayed(const Duration(milliseconds: 100));

          // Then emit with 1 expense (Alice only)
          expensesStateController.add(ExpensesLoaded(expenses: [testExpense1]));
          await Future.delayed(const Duration(milliseconds: 100));
        },
        expect: () => [
          const FriendsLoading(),
          isA<FriendsLoaded>().having(
            (s) => s.friends.length,
            'friends count (first)',
            2,
          ),
          const FriendsLoading(),
          isA<FriendsLoaded>()
              .having((s) => s.friends.length, 'friends count (updated)', 1)
              .having((s) => s.friends.first.name, 'friend name', 'Alice'),
        ],
      );

      blocTest<FriendsBloc, FriendsState>(
        'ignores non-loaded states from ExpensesBloc',
        build: () => bloc,
        act: (bloc) async {
          expensesStateController.add(const ExpensesLoading());
          await Future.delayed(const Duration(milliseconds: 100));
          expensesStateController.add(const ExpensesRefreshing());
          await Future.delayed(const Duration(milliseconds: 100));
        },
        expect: () => [],
      );
    });

    group('Friend extraction logic', () {
      blocTest<FriendsBloc, FriendsState>(
        'extracts friends from descriptions with "with" keyword',
        build: () {
          final expenses = [
            Expense(
              core: ExpenseCore(
                id: '1',
                title: 'Lunch',
                amount: 50.0,
                currency: 'USD',
                category: 'Food',
                createdAt: DateTime.now(),
              ),
              description: 'Lunch with Charlie',
            ),
            Expense(
              core: ExpenseCore(
                id: '2',
                title: 'Dinner',
                amount: 100.0,
                currency: 'USD',
                category: 'Food',
                createdAt: DateTime.now(),
              ),
              description: 'Dinner with Charlie and David',
            ),
          ];
          when(
            () => mockExpensesBloc.state,
          ).thenReturn(ExpensesLoaded(expenses: expenses));
          return bloc;
        },
        act: (bloc) => bloc.add(const LoadFriends()),
        verify: (_) {
          final state = bloc.state as FriendsLoaded;
          expect(state.friends.length, 2);
          expect(state.friends.any((f) => f.name == 'Charlie'), true);
          expect(state.friends.any((f) => f.name == 'David'), true);
        },
      );

      blocTest<FriendsBloc, FriendsState>(
        'handles case-insensitive friend names',
        build: () {
          final expenses = [
            Expense(
              core: ExpenseCore(
                id: '1',
                title: 'Lunch',
                amount: 50.0,
                currency: 'USD',
                category: 'Food',
                createdAt: DateTime.now(),
              ),
              description: 'with alice',
            ),
            Expense(
              core: ExpenseCore(
                id: '2',
                title: 'Dinner',
                amount: 100.0,
                currency: 'USD',
                category: 'Food',
                createdAt: DateTime.now(),
              ),
              description: 'WITH ALICE',
            ),
          ];
          when(
            () => mockExpensesBloc.state,
          ).thenReturn(ExpensesLoaded(expenses: expenses));
          return bloc;
        },
        act: (bloc) => bloc.add(const LoadFriends()),
        verify: (_) {
          final state = bloc.state as FriendsLoaded;
          expect(state.friends.length, 1); // Same friend, different cases
          expect(state.friends.first.expenseCount, 2);
        },
      );
    });
  });
}
