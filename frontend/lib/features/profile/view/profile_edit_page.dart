import 'package:expense_tracker/features/profile/cubit/profile_edit_cubit.dart';
import 'package:expense_tracker/features/profile/cubit/profile_edit_state.dart';
import 'package:expense_tracker/features/profile/models/user_profile.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({
    required this.user,
    required this.profile,
    required this.repository,
    super.key,
  });

  final User user;
  final UserProfile profile;
  final UserProfileRepository repository;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final ProfileEditCubit _cubit;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _nameController.addListener(_onNameChanged);
    _emailController = TextEditingController(text: widget.profile.email);
    _cubit = ProfileEditCubit(
      repository: widget.repository,
      initialPhotoUrl: widget.profile.photoUrl,
    );
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _emailController.dispose();
    _cubit.close();
    super.dispose();
  }

  void _onNameChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;

      await _cubit.uploadPhoto(
        user: widget.user,
        bytes: bytes,
        fileNameHint: file.name,
      );
    } catch (error) {
      _cubit.onImagePickFailed(error);
    }
  }

  Future<void> _save() {
    return _cubit.saveDisplayName(
      user: widget.user,
      displayName: _nameController.text,
      initialDisplayName: widget.profile.displayName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasNameChanges =
        _nameController.text.trim() != widget.profile.displayName;
    const avatarDiameter = 88.0;

    return BlocProvider.value(
      value: _cubit,
      child: BlocConsumer<ProfileEditCubit, ProfileEditState>(
        listenWhen: (previous, current) =>
            previous.action != current.action &&
            current.action != ProfileEditAction.none,
        listener: (context, state) {
          if (state.action == ProfileEditAction.profileSaved) {
            Navigator.of(context).pop(true);
          }
        },
        builder: (context, state) {
          final busy = state.isBusy;
          return Scaffold(
            appBar: AppBar(title: const Text('Edit profile')),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Align(
                      child: SizedBox(
                        width: avatarDiameter,
                        height: avatarDiameter,
                        child: ClipOval(
                          child: state.pickedImageBytes != null
                              ? Image.memory(
                                  state.pickedImageBytes!,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _AvatarFallback(iconSize: 44),
                                )
                              : (state.photoUrl?.isNotEmpty == true
                                    ? Image.network(
                                        state.photoUrl!,
                                        key: ValueKey(
                                          '${state.photoUrl}|${state.avatarVersion}',
                                        ),
                                        webHtmlElementStrategy:
                                            WebHtmlElementStrategy.prefer,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                _AvatarFallback(iconSize: 44),
                                      )
                                    : const _AvatarFallback(iconSize: 44)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      child: TextButton.icon(
                        onPressed: busy ? null : _pickPhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Change photo'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (state.pickedImageName != null)
                      Text(
                        'Selected image: ${state.pickedImageName}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (state.pickedImageName != null)
                      const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailController,
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (state.error != null) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        state.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (state.message != null) ...[
                      const SizedBox(height: 12),
                      Text(state.message!),
                    ],
                    if (state.status == ProfileEditStatus.uploadingPhoto &&
                        state.uploadProgress != null) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: state.uploadProgress,
                        minHeight: 6,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(state.uploadProgress! * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                      ),
                    ],
                    if (hasNameChanges) ...[
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: busy ? null : _save,
                        child: state.status == ProfileEditStatus.savingName
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.iconSize});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
      alignment: Alignment.center,
      child: Icon(Icons.person, size: iconSize),
    );
  }
}
