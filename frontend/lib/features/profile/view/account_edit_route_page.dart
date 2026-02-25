import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/profile/models/user_profile.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:expense_tracker/features/profile/view/profile_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AccountEditRoutePage extends StatelessWidget {
  const AccountEditRoutePage({required this.profileRepository, super.key});

  final UserProfileRepository profileRepository;

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthCubit cubit) => cubit.state.user);
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: SelectableErrorMessage('No authenticated user found.'),
        ),
      );
    }

    return StreamBuilder<UserProfile>(
      stream: profileRepository.watchProfile(user),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit profile')),
            body: Center(
              child: SelectableErrorMessage(snapshot.error.toString()),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit profile')),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return ProfileEditPage(
          user: user,
          profile: snapshot.data!,
          repository: profileRepository,
        );
      },
    );
  }
}
