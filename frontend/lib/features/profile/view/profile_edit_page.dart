import 'dart:typed_data';

import 'package:expense_tracker/features/profile/models/user_profile.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  final _picker = ImagePicker();
  Uint8List? _pickedImageBytes;
  String? _pickedImageName;
  String? _photoUrl;
  bool _saving = false;
  bool _uploadingPhoto = false;
  double? _uploadProgress;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _nameController.addListener(_onNameChanged);
    _emailController = TextEditingController(text: widget.profile.email);
    _photoUrl = widget.profile.photoUrl;
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _emailController.dispose();
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
      if (file == null) {
        setState(() {
          _status = 'Photo selection cancelled.';
          _error = null;
        });
        return;
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        setState(() {
          _error = 'Selected image is empty. Try a different image.';
          _status = null;
        });
        return;
      }

      setState(() {
        _pickedImageBytes = bytes;
        _pickedImageName = file.name;
        _error = null;
        _status = 'Selected ${file.name}. Uploading...';
      });

      await _uploadSelectedPhoto();
    } catch (error) {
      setState(() {
        _error = 'Failed to pick image: $error';
        _status = null;
      });
    }
  }

  Future<void> _uploadSelectedPhoto() async {
    final bytes = _pickedImageBytes;
    if (bytes == null) return;

    setState(() {
      _uploadingPhoto = true;
      _uploadProgress = 0;
      _error = null;
      _status = 'Uploading profile photo...';
    });
    try {
      final downloadUrl = await widget.repository.uploadProfilePhoto(
        user: widget.user,
        bytes: bytes,
        fileNameHint: _pickedImageName ?? 'profile_photo.jpg',
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _uploadProgress = value.clamp(0, 1).toDouble());
        },
      );
      if (!mounted) return;
      setState(() {
        _photoUrl = downloadUrl;
        _pickedImageName = null;
        _status = 'Profile photo uploaded successfully.';
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _error =
            'Failed to upload photo (${error.code}): ${error.message ?? 'Unknown Firebase error'}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to upload photo: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPhoto = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name cannot be empty.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _status = 'Saving profile...';
    });
    try {
      if (name != widget.profile.displayName) {
        setState(() => _status = 'Updating display name...');
        await widget.repository.updateDisplayName(
          user: widget.user,
          displayName: name,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _error =
            'Failed to save profile (${error.code}): ${error.message ?? 'Unknown Firebase error'}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Failed to save profile: $error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _status = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasNameChanges =
        _nameController.text.trim() != widget.profile.displayName;
    final avatarDiameter = 88.0;

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
                    child: _pickedImageBytes != null
                        ? Image.memory(
                            _pickedImageBytes!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _AvatarFallback(iconSize: 44),
                          )
                        : (_photoUrl?.isNotEmpty == true
                              ? Image.network(
                                  _photoUrl!,
                                  key: ValueKey(_photoUrl),
                                  fit: BoxFit.cover,
                                  webHtmlElementStrategy:
                                      WebHtmlElementStrategy.prefer,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _AvatarFallback(iconSize: 44),
                                )
                              : const _AvatarFallback(iconSize: 44)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                child: TextButton.icon(
                  onPressed: (_saving || _uploadingPhoto) ? null : _pickPhoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Change photo'),
                ),
              ),
              const SizedBox(height: 12),
              if (_pickedImageName != null)
                Text(
                  'Selected image: $_pickedImageName',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (_pickedImageName != null) const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                enabled: !_saving && !_uploadingPhoto,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(_status!),
                if (_uploadingPhoto || _uploadProgress != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _uploadProgress, minHeight: 6),
                ],
                if (_uploadingPhoto && _uploadProgress != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${(_uploadProgress! * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                  ),
                ],
              ],
              if (hasNameChanges) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: (_saving || _uploadingPhoto) ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ],
          ),
        ),
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
