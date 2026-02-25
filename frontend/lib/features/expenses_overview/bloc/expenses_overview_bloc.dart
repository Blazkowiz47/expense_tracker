import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'expenses_overview_event.dart';
part 'expenses_overview_state.dart';

class ExpensesOverviewBloc
    extends Bloc<ExpensesOverviewEvent, ExpensesOverviewState> {
  ExpensesOverviewBloc() : super(ExpensesOverviewInitial()) {
    on<ExpensesOverviewEvent>((event, emit) {
      // TODO: implement event handler
    });
  }
}
