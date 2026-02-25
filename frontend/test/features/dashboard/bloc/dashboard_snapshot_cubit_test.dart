import 'package:bloc_test/bloc_test.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardSnapshotCubit', () {
    blocTest<DashboardSnapshotCubit, DashboardSnapshotState>(
      'emits loading then loaded snapshot',
      build: () => DashboardSnapshotCubit(
        repository: const MockDashboardSnapshotRepository(),
      ),
      act: (cubit) => cubit.load(),
      expect: () => [
        const DashboardSnapshotLoading(),
        isA<DashboardSnapshotLoaded>(),
      ],
    );
  });
}
