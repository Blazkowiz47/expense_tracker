import 'package:expense_tracker/app/app.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/auth/repositories/auth_repository.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:expense_tracker/features/profile/models/user_profile.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.user});

  final AuthUser? user;

  @override
  Stream<AuthUser?> authStateChanges() => Stream<AuthUser?>.value(user);

  @override
  Future<void> login({required String email, required String password}) async {}

  @override
  Future<void> loginWithGoogle() async {}

  @override
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class _FakeExpensesRepository extends ExpenseRepository {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> refresh() async {}

  @override
  List<Expense> getExpenses() => const [];
}

class _FakeProfileRepository extends UserProfileRepository {
  @override
  Future<void> ensureUserDocument(AuthUser user) async {}

  @override
  Stream<UserProfile> watchProfile(AuthUser user) async* {
    yield UserProfile(
      uid: user.uid,
      displayName: user.displayName,
      email: user.email,
      photoUrl: user.photoUrl,
      onboardingCompleted: user.onboardingCompleted,
      defaultPaymentMethod: user.defaultPaymentMethod,
    );
  }

  @override
  Future<UserProfile> fetchProfile({required AuthUser fallback}) async {
    return UserProfile(
      uid: fallback.uid,
      displayName: fallback.displayName,
      email: fallback.email,
      photoUrl: fallback.photoUrl,
      onboardingCompleted: fallback.onboardingCompleted,
      defaultPaymentMethod: fallback.defaultPaymentMethod,
    );
  }
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
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('authenticated app boots into usable home shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ExpenseTrackerApp(
        authRepository: _FakeAuthRepository(
          user: const AuthUser(
            uid: 'smoke-user',
            email: 'smoke@example.com',
            displayName: 'Smoke User',
            onboardingCompleted: true,
          ),
        ),
        dashboardRepository: const MockDashboardSnapshotRepository(),
        expensesRepository: _FakeExpensesRepository(),
        profileRepository: _FakeProfileRepository(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Expense tracker'), findsWidgets);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Family'), findsWidgets);
    expect(find.text('Activity'), findsWidgets);
    expect(find.text('Account'), findsWidgets);
    expect(find.byTooltip('Add expense'), findsWidgets);
  });
}
