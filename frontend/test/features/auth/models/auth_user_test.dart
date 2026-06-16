import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses and serializes onboarding completion', () {
    final user = AuthUser.fromJson(const {
      'uid': 'u1',
      'email': 'person@example.com',
      'displayName': 'Person',
      'onboardingCompleted': true,
    });

    expect(user.onboardingCompleted, isTrue);
    expect(user.toJson()['onboardingCompleted'], isTrue);
    expect(
      user.copyWith(onboardingCompleted: false).onboardingCompleted,
      false,
    );
  });

  test('defaults onboarding to incomplete for older cached users', () {
    final user = AuthUser.fromJson(const {
      'uid': 'u1',
      'email': 'person@example.com',
      'displayName': 'Person',
    });

    expect(user.onboardingCompleted, isFalse);
  });
}
