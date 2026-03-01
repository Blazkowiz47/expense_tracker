import 'package:expense_tracker/app/app.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Stream<User?> authStateChanges() => Stream<User?>.value(null);

  @override
  Future<void> signInWithGoogle() async {}

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
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
