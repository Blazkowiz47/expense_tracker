class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    this.onboardingCompleted = false,
  });

  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final bool onboardingCompleted;
}
