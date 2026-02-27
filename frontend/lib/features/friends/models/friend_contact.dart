import 'package:equatable/equatable.dart';

class FriendContact extends Equatable {
  const FriendContact({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.phone,
  });

  final String uid;
  final String displayName;
  final String email;
  final String phone;

  factory FriendContact.fromJson(Map<String, dynamic> json) {
    return FriendContact(
      uid: (json['uid'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
    );
  }

  String get label {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (email.trim().isNotEmpty) return email.trim();
    if (phone.trim().isNotEmpty) return phone.trim();
    return uid;
  }

  String get contactHint {
    if (email.trim().isNotEmpty) return email.trim();
    if (phone.trim().isNotEmpty) return phone.trim();
    return '';
  }

  @override
  List<Object?> get props => [uid, displayName, email, phone];
}

class FriendResolveResult extends Equatable {
  const FriendResolveResult({
    required this.exists,
    this.uid,
    this.displayName,
    this.email,
    this.phone,
  });

  final bool exists;
  final String? uid;
  final String? displayName;
  final String? email;
  final String? phone;

  factory FriendResolveResult.fromJson(Map<String, dynamic> json) {
    return FriendResolveResult(
      exists: json['exists'] as bool? ?? false,
      uid: (json['uid'] as String?)?.trim().isEmpty == true
          ? null
          : json['uid'] as String?,
      displayName: (json['displayName'] as String?)?.trim().isEmpty == true
          ? null
          : json['displayName'] as String?,
      email: (json['email'] as String?)?.trim().isEmpty == true
          ? null
          : json['email'] as String?,
      phone: (json['phone'] as String?)?.trim().isEmpty == true
          ? null
          : json['phone'] as String?,
    );
  }

  String get label {
    final name = displayName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    final em = email?.trim() ?? '';
    if (em.isNotEmpty) return em;
    final ph = phone?.trim() ?? '';
    if (ph.isNotEmpty) return ph;
    return uid ?? '';
  }

  @override
  List<Object?> get props => [exists, uid, displayName, email, phone];
}
