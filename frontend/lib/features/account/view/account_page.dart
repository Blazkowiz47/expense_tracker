import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/profile/models/user_profile.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:expense_tracker/features/profile/view/profile_edit_page.dart';
import 'package:expense_tracker/features/theme/view/theme_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({this.profileRepository, super.key});

  final UserProfileRepository? profileRepository;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardSnapshotCubit, DashboardSnapshotState>(
      builder: (context, state) {
        if (state is DashboardSnapshotFailure) {
          return SelectableErrorMessage(state.message);
        }

        if (state is! DashboardSnapshotLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final user = context.select((AuthCubit cubit) => cubit.state.user);
        if (user == null) {
          return const SelectableErrorMessage('No authenticated user found.');
        }
        final repo = profileRepository ?? UserProfileRepository();

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: StreamBuilder<UserProfile>(
              stream: repo.watchProfile(user),
              builder: (context, profileSnapshot) {
                final profile =
                    profileSnapshot.data ??
                    UserProfile(
                      uid: user.uid,
                      displayName: user.displayName ?? 'User',
                      email: user.email ?? '',
                      photoUrl: user.photoURL,
                    );

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _ProfileCard(
                      profile: profile,
                      onEdit: () async {
                        await Navigator.of(context).push<bool>(
                          MaterialPageRoute<bool>(
                            builder: (_) => ProfileEditPage(
                              user: user,
                              profile: profile,
                              repository: repo,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const _SettingsTile(title: 'Notifications'),
                    const _SettingsTile(title: 'Security'),
                    _SettingsTile(
                      title: 'Theme',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ThemeSettingsPage(),
                          ),
                        );
                      },
                    ),
                    const _SettingsTile(title: 'Help and feedback'),
                    _SettingsTile(
                      title: 'Logout',
                      onTap: () => context.read<AuthCubit>().signOut(),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.onEdit});

  final UserProfile profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final photoProvider = profile.photoUrl?.isNotEmpty == true
        ? NetworkImage(profile.photoUrl!)
        : null;
    return Card(
      child: ListTile(
        onTap: onEdit,
        leading: CircleAvatar(
          backgroundImage: photoProvider,
          child: photoProvider == null ? const Icon(Icons.person) : null,
        ),
        title: Text(profile.displayName),
        subtitle: Text(profile.email),
        trailing: TextButton(onPressed: onEdit, child: const Text('Edit')),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.title, this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
