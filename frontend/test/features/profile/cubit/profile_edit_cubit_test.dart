import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:expense_tracker/features/profile/cubit/profile_edit_cubit.dart';
import 'package:expense_tracker/features/profile/cubit/profile_edit_state.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUserProfileRepository extends Mock
    implements UserProfileRepository {}

class _MockUser extends Mock implements User {}

class _FakeUser extends Fake implements User {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeUser());
    registerFallbackValue(Uint8List.fromList(<int>[]));
  });

  group('ProfileEditCubit', () {
    late UserProfileRepository repository;
    late User user;

    setUp(() {
      repository = _MockUserProfileRepository();
      user = _MockUser();
    });

    test('has initial photo url when provided', () {
      final cubit = ProfileEditCubit(
        repository: repository,
        initialPhotoUrl: 'https://example.com/a.jpg',
      );
      expect(cubit.state.photoUrl, 'https://example.com/a.jpg');
    });

    blocTest<ProfileEditCubit, ProfileEditState>(
      'uploadPhoto emits uploading then success',
      setUp: () {
        when(
          () => repository.uploadProfilePhoto(
            user: any(named: 'user'),
            bytes: any(named: 'bytes'),
            fileNameHint: any(named: 'fileNameHint'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async => 'https://example.com/profile.jpg');
      },
      build: () => ProfileEditCubit(repository: repository),
      act: (cubit) => cubit.uploadPhoto(
        user: user,
        bytes: Uint8List.fromList([1, 2, 3]),
        fileNameHint: 'a.jpg',
      ),
      expect: () => [
        isA<ProfileEditState>()
            .having(
              (state) => state.status,
              'status',
              ProfileEditStatus.uploadingPhoto,
            )
            .having((state) => state.uploadProgress, 'uploadProgress', 0)
            .having(
              (state) => state.pickedImageName,
              'pickedImageName',
              'a.jpg',
            ),
        isA<ProfileEditState>()
            .having(
              (state) => state.status,
              'status',
              ProfileEditStatus.success,
            )
            .having(
              (state) => state.action,
              'action',
              ProfileEditAction.photoUploaded,
            )
            .having(
              (state) => state.pickedImageBytes,
              'pickedImageBytes',
              isNotNull,
            )
            .having((state) => state.avatarVersion, 'avatarVersion', 1)
            .having(
              (state) => state.photoUrl,
              'photoUrl',
              contains('profile.jpg'),
            ),
      ],
    );

    blocTest<ProfileEditCubit, ProfileEditState>(
      'saveDisplayName emits saving then profileSaved',
      setUp: () {
        when(
          () => repository.updateDisplayName(
            user: any(named: 'user'),
            displayName: any(named: 'displayName'),
          ),
        ).thenAnswer((_) async {});
      },
      build: () => ProfileEditCubit(repository: repository),
      act: (cubit) => cubit.saveDisplayName(
        user: user,
        displayName: 'Updated Name',
        initialDisplayName: 'Old Name',
      ),
      expect: () => [
        const ProfileEditState(
          status: ProfileEditStatus.savingName,
          action: ProfileEditAction.none,
          message: 'Updating display name...',
        ),
        const ProfileEditState(
          status: ProfileEditStatus.success,
          action: ProfileEditAction.profileSaved,
          message: 'Profile updated successfully.',
        ),
      ],
    );
  });
}
