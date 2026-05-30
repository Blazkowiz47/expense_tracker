import 'dart:typed_data';

import 'package:expense_tracker/features/auth/models/auth_user.dart';
import 'package:expense_tracker/features/profile/cubit/profile_edit_cubit.dart';
import 'package:expense_tracker/features/profile/models/user_profile.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:expense_tracker/features/profile/view/profile_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUserProfileRepository extends Mock
    implements UserProfileRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AuthUser(
        uid: 'uid-1',
        email: 'user@example.com',
        displayName: 'User',
      ),
    );
    registerFallbackValue(Uint8List.fromList(<int>[]));
  });

  testWidgets('keeps in-memory avatar visible after photo upload success', (
    tester,
  ) async {
    final repository = _MockUserProfileRepository();
    const user = AuthUser(
      uid: 'uid-1',
      email: 'user@example.com',
      displayName: 'User',
    );
    const profile = UserProfile(
      uid: 'uid-1',
      displayName: 'User',
      email: 'user@example.com',
    );

    when(
      () => repository.uploadProfilePhoto(
        user: any(named: 'user'),
        bytes: any(named: 'bytes'),
        fileNameHint: any(named: 'fileNameHint'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) async => 'https://example.com/profile.jpg');

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditPage(
          user: user,
          profile: profile,
          repository: repository,
        ),
      ),
    );

    final scaffoldContext = tester.element(find.byType(Scaffold));
    final cubit = BlocProvider.of<ProfileEditCubit>(scaffoldContext);
    final bytes = Uint8List.fromList(_onePxTransparentPng);

    await cubit.uploadPhoto(user: user, bytes: bytes, fileNameHint: 'a.png');
    await tester.pumpAndSettle();

    expect(find.text('Profile photo uploaded successfully.'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is MemoryImage &&
            widget.gaplessPlayback,
      ),
      findsOneWidget,
    );
  });
}

const _onePxTransparentPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
