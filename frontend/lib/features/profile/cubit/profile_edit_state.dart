import 'package:equatable/equatable.dart';

enum ProfileEditStatus { idle, uploadingPhoto, savingName, success, failure }

enum ProfileEditAction { none, photoUploaded, profileSaved }

class ProfileEditState extends Equatable {
  const ProfileEditState({
    this.status = ProfileEditStatus.idle,
    this.action = ProfileEditAction.none,
    this.uploadProgress,
    this.photoUrl,
    this.message,
    this.error,
  });

  final ProfileEditStatus status;
  final ProfileEditAction action;
  final double? uploadProgress;
  final String? photoUrl;
  final String? message;
  final String? error;

  bool get isBusy =>
      status == ProfileEditStatus.uploadingPhoto ||
      status == ProfileEditStatus.savingName;

  ProfileEditState copyWith({
    ProfileEditStatus? status,
    ProfileEditAction? action,
    double? uploadProgress,
    bool clearUploadProgress = false,
    String? photoUrl,
    bool clearPhotoUrl = false,
    String? message,
    bool clearMessage = false,
    String? error,
    bool clearError = false,
  }) {
    return ProfileEditState(
      status: status ?? this.status,
      action: action ?? this.action,
      uploadProgress: clearUploadProgress
          ? null
          : (uploadProgress ?? this.uploadProgress),
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      message: clearMessage ? null : (message ?? this.message),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
    status,
    action,
    uploadProgress,
    photoUrl,
    message,
    error,
  ];
}
