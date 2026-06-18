import 'package:bloc_test/bloc_test.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

void main() {
  group('DashboardSnapshotCubit', () {
    setUp(() async {
      await HydratedBloc.storage.clear();
    });

    blocTest<DashboardSnapshotCubit, DashboardSnapshotState>(
      'emits loading then loaded snapshot',
      build: () => DashboardSnapshotCubit(
        repository: const MockDashboardSnapshotRepository(),
      ),
      act: (cubit) => cubit.load(),
      expect: () => [
        const DashboardSnapshotLoading(),
        isA<DashboardSnapshotLoaded>().having(
          (state) => state.loadingAiInsights,
          'loadingAiInsights',
          isTrue,
        ),
        isA<DashboardSnapshotLoaded>().having(
          (state) => state.loadingAiInsights,
          'loadingAiInsights',
          isFalse,
        ),
      ],
    );

    test(
      'silent refresh keeps the last loaded snapshot when fetch fails',
      () async {
        final repository = _FailingAfterFirstSnapshotRepository();
        final cubit = DashboardSnapshotCubit(repository: repository);
        await cubit.load();
        await Future<void>.delayed(Duration.zero);
        final loadedState = cubit.state;

        await cubit.load(showLoading: false);

        expect(loadedState, isA<DashboardSnapshotLoaded>());
        expect(cubit.state, same(loadedState));
        await cubit.close();
      },
    );

    test('hydrates the last loaded snapshot for instant home paint', () async {
      final first = DashboardSnapshotCubit(
        repository: const MockDashboardSnapshotRepository(),
      );
      await first.load();
      await Future<void>.delayed(Duration.zero);
      expect(first.state, isA<DashboardSnapshotLoaded>());
      await first.close();

      final restored = DashboardSnapshotCubit(
        repository: const MockDashboardSnapshotRepository(),
      );
      addTearDown(restored.close);

      final state = restored.state;
      expect(state, isA<DashboardSnapshotLoaded>());
      expect(
        (state as DashboardSnapshotLoaded).snapshot.accountName,
        'Sushrut Patwardhan',
      );
      expect(state.loadingAiInsights, isFalse);
    });
  });
}

class _FailingAfterFirstSnapshotRepository
    implements DashboardSnapshotRepository {
  var _calls = 0;

  @override
  Future<DashboardSnapshot> fetchSnapshot() async {
    _calls += 1;
    if (_calls == 1) {
      return const MockDashboardSnapshotRepository().fetchSnapshot();
    }
    throw Exception('offline');
  }

  @override
  Future<List<AiInsight>> fetchAiInsights() async => const [];
}
