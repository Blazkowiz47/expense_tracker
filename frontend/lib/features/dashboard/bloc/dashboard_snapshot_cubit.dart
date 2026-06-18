import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'dashboard_snapshot_state.dart';

class DashboardSnapshotCubit extends HydratedCubit<DashboardSnapshotState> {
  DashboardSnapshotCubit({required DashboardSnapshotRepository repository})
    : _repository = repository,
      super(const DashboardSnapshotLoading());

  final DashboardSnapshotRepository _repository;

  Future<void> load({bool showLoading = true}) async {
    if (showLoading && state is! DashboardSnapshotLoaded) {
      emit(const DashboardSnapshotLoading());
    }
    try {
      final snapshot = await _repository.fetchSnapshot();
      emit(
        DashboardSnapshotLoaded(snapshot: snapshot, loadingAiInsights: true),
      );
      unawaited(_loadAiInsights());
    } catch (error) {
      if (showLoading || state is! DashboardSnapshotLoaded) {
        emit(DashboardSnapshotFailure(message: error.toString()));
      }
    }
  }

  Future<void> _loadAiInsights() async {
    try {
      final insights = await _repository.fetchAiInsights();
      if (isClosed) return;
      final current = state;
      if (current is! DashboardSnapshotLoaded) return;
      emit(
        DashboardSnapshotLoaded(
          snapshot: current.snapshot.copyWith(aiInsights: insights),
        ),
      );
    } catch (_) {
      if (isClosed) return;
      final current = state;
      if (current is! DashboardSnapshotLoaded) return;
      emit(DashboardSnapshotLoaded(snapshot: current.snapshot));
    }
  }

  @override
  DashboardSnapshotState? fromJson(Map<String, dynamic> json) {
    final snapshot = json['snapshot'];
    if (snapshot is! Map<String, dynamic>) return null;
    return DashboardSnapshotLoaded(
      snapshot: DashboardSnapshot.fromJson(snapshot),
    );
  }

  @override
  Map<String, dynamic>? toJson(DashboardSnapshotState state) {
    if (state is! DashboardSnapshotLoaded) return null;
    return {'snapshot': state.snapshot.toJson()};
  }
}
