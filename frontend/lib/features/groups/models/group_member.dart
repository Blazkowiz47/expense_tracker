class GroupMember {
  const GroupMember({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.phone,
  });

  final String uid;
  final String displayName;
  final String email;
  final String phone;

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      uid: (json['uid'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
    );
  }

  String get label {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (email.trim().isNotEmpty) return email.trim();
    if (phone.trim().isNotEmpty) return phone.trim();
    return uid;
  }
}
