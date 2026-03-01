import 'package:expense_tracker/app/view/app.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:flutter/widgets.dart';

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({this.authRepository, super.key});

  final AuthRepository? authRepository;

  @override
  Widget build(BuildContext context) {
    return ExpenseTrackerAppView(authRepository: authRepository);
  }
}
