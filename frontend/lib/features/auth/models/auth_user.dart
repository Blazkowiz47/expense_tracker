import 'package:equatable/equatable.dart';

class AuthUser extends Equatable {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.phone,
    this.onboardingCompleted = false,
  });

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? phone;
  final bool onboardingCompleted;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      uid: (json['uid'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? 'User',
      photoUrl: json['photoUrl'] as String?,
      phone: json['phone'] as String?,
      onboardingCompleted: (json['onboardingCompleted'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'phone': phone,
      'onboardingCompleted': onboardingCompleted,
    };
  }

  AuthUser copyWith({
    String? displayName,
    String? photoUrl,
    bool? onboardingCompleted,
  }) {
    return AuthUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      phone: phone,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }

  @override
  List<Object?> get props => [
    uid,
    email,
    displayName,
    photoUrl,
    phone,
    onboardingCompleted,
  ];
}
