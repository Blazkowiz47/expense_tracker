part of 'dashboard_snapshot_cubit.dart';

sealed class DashboardSnapshotState extends Equatable {
  const DashboardSnapshotState();

  @override
  List<Object?> get props => [];
}

final class DashboardSnapshotLoading extends DashboardSnapshotState {
  const DashboardSnapshotLoading();
}

final class DashboardSnapshotLoaded extends DashboardSnapshotState {
  const DashboardSnapshotLoaded({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  List<Object?> get props => [snapshot];
}

final class DashboardSnapshotFailure extends DashboardSnapshotState {
  const DashboardSnapshotFailure({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}
