import 'dart:typed_data';

import 'package:expense_tracker/features/profile/cubit/profile_edit_state.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ProfileEditCubit extends Cubit<ProfileEditState> {
  ProfileEditCubit({
    required UserProfileRepository repository,
    String? initialPhotoUrl,
  }) : _repository = repository,
       super(ProfileEditState(photoUrl: initialPhotoUrl));

  final UserProfileRepository _repository;

  Future<void> uploadPhoto({
    required User user,
    required Uint8List bytes,
    required String fileNameHint,
  }) async {
    emit(
      state.copyWith(
        status: ProfileEditStatus.uploadingPhoto,
        action: ProfileEditAction.none,
        uploadProgress: 0,
        pickedImageBytes: bytes,
        pickedImageName: fileNameHint,
        clearError: true,
        clearMessage: true,
      ),
    );

    try {
      final downloadUrl = await _repository.uploadProfilePhoto(
        user: user,
        bytes: bytes,
        fileNameHint: fileNameHint,
        onProgress: (value) {
          emit(state.copyWith(uploadProgress: value.clamp(0, 1).toDouble()));
        },
      );
      emit(
        state.copyWith(
          status: ProfileEditStatus.success,
          action: ProfileEditAction.photoUploaded,
          photoUrl: _withCacheBuster(downloadUrl),
          clearUploadProgress: true,
          avatarVersion: state.avatarVersion + 1,
          message: 'Profile photo uploaded successfully.',
          clearError: true,
        ),
      );
    } on FirebaseException catch (error) {
      emit(
        state.copyWith(
          status: ProfileEditStatus.failure,
          action: ProfileEditAction.none,
          clearUploadProgress: true,
          clearMessage: true,
          error:
              'Failed to upload photo (${error.code}): ${error.message ?? 'Unknown Firebase error'}',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: ProfileEditStatus.failure,
          action: ProfileEditAction.none,
          clearUploadProgress: true,
          clearMessage: true,
          error: 'Failed to upload photo: $error',
        ),
      );
    }
  }

  void onImagePickFailed(Object error) {
    emit(
      state.copyWith(
        status: ProfileEditStatus.failure,
        action: ProfileEditAction.none,
        error: 'Failed to pick image: $error',
        clearMessage: true,
        clearUploadProgress: true,
      ),
    );
  }

  Future<void> saveDisplayName({
    required User user,
    required String displayName,
    required String initialDisplayName,
  }) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      emit(
        state.copyWith(
          status: ProfileEditStatus.failure,
          action: ProfileEditAction.none,
          clearMessage: true,
          error: 'Name cannot be empty.',
        ),
      );
      return;
    }
    if (trimmed == initialDisplayName) return;

    emit(
      state.copyWith(
        status: ProfileEditStatus.savingName,
        action: ProfileEditAction.none,
        clearError: true,
        message: 'Updating display name...',
      ),
    );

    try {
      await _repository.updateDisplayName(user: user, displayName: trimmed);
      emit(
        state.copyWith(
          status: ProfileEditStatus.success,
          action: ProfileEditAction.profileSaved,
          message: 'Profile updated successfully.',
          clearError: true,
        ),
      );
    } on FirebaseException catch (error) {
      emit(
        state.copyWith(
          status: ProfileEditStatus.failure,
          action: ProfileEditAction.none,
          clearMessage: true,
          error:
              'Failed to save profile (${error.code}): ${error.message ?? 'Unknown Firebase error'}',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: ProfileEditStatus.failure,
          action: ProfileEditAction.none,
          clearMessage: true,
          error: 'Failed to save profile: $error',
        ),
      );
    }
  }

  String _withCacheBuster(String url) {
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}v=${DateTime.now().millisecondsSinceEpoch}';
  }
}
