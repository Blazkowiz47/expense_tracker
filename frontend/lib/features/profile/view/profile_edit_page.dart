import 'dart:typed_data';

import 'package:expense_tracker/features/profile/models/user_profile.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  bool _saving = false;
  bool _uploadingPhoto = false;
  double? _uploadProgress;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _emailController = TextEditingController(text: widget.profile.email);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
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
      await widget.repository.uploadProfilePhoto(
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
    final photoProvider = _pickedImageBytes != null
        ? MemoryImage(_pickedImageBytes!)
        : (widget.profile.photoUrl?.isNotEmpty == true
                  ? NetworkImage(widget.profile.photoUrl!)
                  : null)
              as ImageProvider<Object>?;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                child: CircleAvatar(
                  radius: 44,
                  backgroundImage: photoProvider,
                  child: photoProvider == null
                      ? const Icon(Icons.person, size: 44)
                      : null,
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
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _uploadProgress, minHeight: 6),
                if (_uploadProgress != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${(_uploadProgress! * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                  ),
                ],
              ],
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
          ),
        ),
      ),
    );
  }
}
