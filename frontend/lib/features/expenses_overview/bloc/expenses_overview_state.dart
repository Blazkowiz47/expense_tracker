part of 'expenses_overview_bloc.dart';

sealed class ExpensesOverviewState extends Equatable {
  const ExpensesOverviewState();

  @override
  List<Object> get props => [];
}

final class ExpensesOverviewInitial extends ExpensesOverviewState {}
