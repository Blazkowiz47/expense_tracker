import 'package:equatable/equatable.dart';

class AuthUser extends Equatable {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.phone,
    this.onboardingCompleted = false,
    this.defaultPaymentMethod = 'cash',
  });

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? phone;
  final bool onboardingCompleted;
  final String defaultPaymentMethod;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      uid: (json['uid'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? 'User',
      photoUrl: json['photoUrl'] as String?,
      phone: json['phone'] as String?,
      onboardingCompleted: (json['onboardingCompleted'] as bool?) ?? false,
      defaultPaymentMethod:
          (json['defaultPaymentMethod'] as String?)?.trim().isNotEmpty == true
          ? (json['defaultPaymentMethod'] as String).trim()
          : 'cash',
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
      'defaultPaymentMethod': defaultPaymentMethod,
    };
  }

  AuthUser copyWith({
    String? displayName,
    String? photoUrl,
    bool? onboardingCompleted,
    String? defaultPaymentMethod,
  }) {
    return AuthUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      phone: phone,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      defaultPaymentMethod: defaultPaymentMethod ?? this.defaultPaymentMethod,
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
    defaultPaymentMethod,
  ];
}
