import 'package:equatable/equatable.dart';

class FriendContact extends Equatable {
  const FriendContact({
    required this.uid,
    required this.displayName,
    required this.email,
  });

  final String uid;
  final String displayName;
  final String email;

  factory FriendContact.fromJson(Map<String, dynamic> json) {
    return FriendContact(
      uid: (json['uid'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
    );
  }

  String get label {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (email.trim().isNotEmpty) return email.trim();
    return uid;
  }

  @override
  List<Object?> get props => [uid, displayName, email];
}

class FriendResolveResult extends Equatable {
  const FriendResolveResult({required this.exists, this.uid});

  final bool exists;
  final String? uid;

  factory FriendResolveResult.fromJson(Map<String, dynamic> json) {
    return FriendResolveResult(
      exists: json['exists'] as bool? ?? false,
      uid: (json['uid'] as String?)?.trim().isEmpty == true
          ? null
          : json['uid'] as String?,
    );
  }

  @override
  List<Object?> get props => [exists, uid];
}
