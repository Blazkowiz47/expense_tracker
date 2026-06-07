import 'package:equatable/equatable.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'dashboard_snapshot_state.dart';

class DashboardSnapshotCubit extends Cubit<DashboardSnapshotState> {
  DashboardSnapshotCubit({required DashboardSnapshotRepository repository})
    : _repository = repository,
      super(const DashboardSnapshotLoading());

  final DashboardSnapshotRepository _repository;

  Future<void> load({bool showLoading = true}) async {
    if (showLoading) {
      emit(const DashboardSnapshotLoading());
    }
    try {
      final snapshot = await _repository.fetchSnapshot();
      emit(DashboardSnapshotLoaded(snapshot: snapshot));
    } catch (error) {
      if (showLoading || state is! DashboardSnapshotLoaded) {
        emit(DashboardSnapshotFailure(message: error.toString()));
      }
    }
  }
}
