import 'dart:typed_data';

import 'package:equatable/equatable.dart';

enum ProfileEditStatus { idle, uploadingPhoto, savingName, success, failure }

enum ProfileEditAction { none, photoUploaded, profileSaved }

class ProfileEditState extends Equatable {
  const ProfileEditState({
    this.status = ProfileEditStatus.idle,
    this.action = ProfileEditAction.none,
    this.uploadProgress,
    this.photoUrl,
    this.pickedImageBytes,
    this.pickedImagePath,
    this.pickedImageName,
    this.avatarVersion = 0,
    this.message,
    this.error,
  });

  final ProfileEditStatus status;
  final ProfileEditAction action;
  final double? uploadProgress;
  final String? photoUrl;
  final Uint8List? pickedImageBytes;
  final String? pickedImagePath;
  final String? pickedImageName;
  final int avatarVersion;
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
    Uint8List? pickedImageBytes,
    bool clearPickedImageBytes = false,
    String? pickedImagePath,
    bool clearPickedImagePath = false,
    String? pickedImageName,
    bool clearPickedImageName = false,
    int? avatarVersion,
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
      pickedImageBytes: clearPickedImageBytes
          ? null
          : (pickedImageBytes ?? this.pickedImageBytes),
      pickedImagePath: clearPickedImagePath
          ? null
          : (pickedImagePath ?? this.pickedImagePath),
      pickedImageName: clearPickedImageName
          ? null
          : (pickedImageName ?? this.pickedImageName),
      avatarVersion: avatarVersion ?? this.avatarVersion,
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
    pickedImageBytes,
    pickedImagePath,
    pickedImageName,
    avatarVersion,
    message,
    error,
  ];
}
