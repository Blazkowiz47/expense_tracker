import 'package:equatable/equatable.dart';

class AuthUser extends Equatable {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.phone,
  });

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? phone;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      uid: (json['uid'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? 'User',
      photoUrl: json['photoUrl'] as String?,
      phone: json['phone'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'phone': phone,
    };
  }

  AuthUser copyWith({String? displayName, String? photoUrl}) {
    return AuthUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      phone: phone,
    );
  }

  @override
  List<Object?> get props => [uid, email, displayName, photoUrl, phone];
}
