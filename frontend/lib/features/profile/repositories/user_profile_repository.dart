import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:expense_tracker/features/profile/models/user_profile.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';

class UserProfileRepository {
  UserProfileRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestoreOverride = firestore,
       _storageOverride = storage;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseStorage? _storageOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  Future<void> ensureUserDocument(User user) async {
    await _upsertUserDoc(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : 'User',
      photoUrl: user.photoURL,
    );
  }

  Stream<UserProfile> watchProfile(User user) {
    final docRef = _firestore.collection('users').doc(user.uid);
    return docRef.snapshots().asyncMap((snapshot) async {
      final data = snapshot.data();
      final displayName =
          (data?['display_name'] as String?)?.trim().isNotEmpty == true
          ? (data?['display_name'] as String).trim()
          : (user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : 'User');
      final email = (data?['email'] as String?) ?? (user.email ?? '');
      final photoUrl = (data?['photo_url'] as String?) ?? user.photoURL;

      if (!snapshot.exists) {
        await ensureUserDocument(user);
      }

      return UserProfile(
        uid: user.uid,
        displayName: displayName,
        email: email,
        photoUrl: photoUrl,
      );
    });
  }

  Future<void> updateDisplayName({
    required User user,
    required String displayName,
  }) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return;

    await _upsertUserDoc(
      uid: user.uid,
      email: user.email,
      displayName: trimmed,
    );
    await user.updateDisplayName(trimmed);
    await user.reload();
  }

  Future<String> uploadProfilePhoto({
    required User user,
    required Uint8List bytes,
    String fileNameHint = 'profile_photo.jpg',
    void Function(double progress)? onProgress,
  }) async {
    final path = 'users/${user.uid}/profile_photo.jpg';
    final contentType = lookupMimeType(fileNameHint) ?? 'image/jpeg';
    final ref = _storage.ref().child(path);
    debugPrint(
      'PROFILE: upload start uid=${user.uid} path=$path contentType=$contentType bytes=${bytes.length}',
    );

    try {
      final task = ref.putData(
        bytes,
        SettableMetadata(
          contentType: contentType,
          cacheControl: 'public,max-age=300',
        ),
      );
      task.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        if (total <= 0) return;
        onProgress?.call(snapshot.bytesTransferred / total);
      });
      await task;
      final downloadUrl = await ref.getDownloadURL();
      debugPrint('PROFILE: upload success uid=${user.uid} url=$downloadUrl');

      await _upsertUserDoc(
        uid: user.uid,
        email: user.email,
        photoUrl: downloadUrl,
      );
      await user.updatePhotoURL(downloadUrl);
      await user.reload();
      return downloadUrl;
    } on FirebaseException catch (error) {
      debugPrint(
        'PROFILE: upload failed uid=${user.uid} code=${error.code} message=${error.message}',
      );
      rethrow;
    }
  }

  Future<void> _upsertUserDoc({
    required String uid,
    String? email,
    String? displayName,
    String? photoUrl,
  }) async {
    final docRef = _firestore.collection('users').doc(uid);
    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      final now = FieldValue.serverTimestamp();
      final data = <String, dynamic>{'uid': uid, 'updated_at': now};

      if (!snap.exists) {
        data['created_at'] = now;
      }
      if (email != null && email.isNotEmpty) {
        data['email'] = email;
      }
      data['email_normalized'] = FieldValue.delete();
      data['emails'] = FieldValue.delete();
      if (displayName != null) {
        data['display_name'] = displayName;
      }
      if (photoUrl != null) {
        data['photo_url'] = photoUrl;
      }

      txn.set(docRef, data, SetOptions(merge: true));
    });
  }
}
