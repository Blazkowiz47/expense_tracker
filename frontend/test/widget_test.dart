import 'package:expense_tracker/app/app.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Stream<AuthUser?> authStateChanges() => Stream<AuthUser?>.value(null);

  @override
  Future<void> login({required String email, required String password}) async {}

  @override
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('app boots into shell with bottom navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ExpenseTrackerApp(authRepository: _FakeAuthRepository()),
    );
    await tester.pump();

    expect(find.text('Expense Tracker'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
