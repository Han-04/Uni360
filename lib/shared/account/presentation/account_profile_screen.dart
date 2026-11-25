import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/photo_upload.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/curved_back_button.dart';
import '../../../features/workforce/worker_profile_repository.dart';
import '../../../features/workforce/worker_profile_section.dart';
import '../account.dart';
import '../account_controller.dart';
import '../account_repository.dart';
import '../supabase_account_repository.dart';
import 'profile_avatar.dart';

class AccountProfileScreen extends StatelessWidget {
  const AccountProfileScreen({
    super.key,
    required this.controller,
    this.workforceDetails,
    this.loadWorkerProfile,
    this.workerStatus,
  });
  final AccountController controller;
  final Widget? workforceDetails;
  final WorkerProfileLoader? loadWorkerProfile;
  final Widget? workerStatus;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final profile = controller.account;
      if (profile == null) return const SizedBox.shrink();
      if (profile.role == AccountRole.worker) {
        return Theme(
          data: buildWorkerTheme(Theme.of(context)),
          child: ColoredBox(
            color: WorkerColors.background,
            child: Builder(
              builder: (context) => _workerProfile(context, profile),
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: AccountAvatar(controller: controller, profile: profile),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              profile.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 21),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  profile.role.label,
                  style: const TextStyle(color: AppColors.muted),
                ),
                ?workerStatus,
              ],
            ),
          ),
          const SectionHeading('Personal details'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReadOnly(label: 'FULL NAME', value: profile.name),
                const SizedBox(height: 16),
                _ReadOnly(
                  label: 'PHONE NUMBER',
                  value: profile.phone.isEmpty ? 'Not added' : profile.phone,
                ),
                const SizedBox(height: 16),
                _ReadOnly(label: 'EMPLOYEE ID', value: profile.employeeId),
                const SizedBox(height: 16),
                _ReadOnly(label: 'EMAIL', value: profile.email),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => _edit(context, profile),
                  child: const Text('Update Profile'),
                ),
              ],
            ),
          ),
          ?workforceDetails,
          const SectionHeading('Account'),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => _PasswordScreen(controller: controller),
              ),
            ),
            icon: const Icon(Icons.lock_outline),
            label: const Text('Change password'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: controller.signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      );
    },
  );

  Future<void> _edit(BuildContext context, Account profile) async {
    final theme = Theme.of(context);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: theme,
          child: _EditProfile(controller: controller, original: profile),
        ),
      ),
    );
    if (changed == true && context.mounted) {
      showMessage(context, 'Profile updated.');
    }
  }

  Widget _workerProfile(BuildContext context, Account profile) => ListView(
    padding: EdgeInsets.fromLTRB(
      18,
      10,
      18,
      24 + MediaQuery.paddingOf(context).bottom,
    ),
    children: [
      SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            AccountAvatar(
              controller: controller,
              profile: profile,
              dimension: 52,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    profile.email,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [Text(profile.role.label), ?workerStatus],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit profile',
              color: WorkerColors.blue,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(context, profile),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      WorkerProfileSection(
        workerId: profile.id,
        load: loadWorkerProfile,
        details: (jobRole) => SurfaceCard(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.badge_outlined,
                  color: WorkerColors.blue,
                ),
                title: const Text('Employee ID'),
                subtitle: Text(profile.employeeId),
              ),
              ListTile(
                leading: const Icon(
                  Icons.phone_outlined,
                  color: WorkerColors.blue,
                ),
                title: const Text('Phone number'),
                subtitle: Text(
                  profile.phone.isEmpty ? 'Not added' : profile.phone,
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.work_outline,
                  color: WorkerColors.blue,
                ),
                title: const Text('Job role'),
                subtitle: Text(jobRole),
              ),
              ListTile(
                title: const Text('Update Profile'),
                leading: const Icon(
                  Icons.manage_accounts_outlined,
                  color: WorkerColors.blue,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _edit(context, profile),
              ),
            ],
          ),
        ),
      ),
      ?workforceDetails,
      const SectionHeading('Account'),
      SurfaceCard(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.lock_outline, color: WorkerColors.blue),
              title: const Text('Change password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => InheritedTheme.captureAll(
                    context,
                    _PasswordScreen(controller: controller),
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: WorkerColors.blue),
              title: const Text('Sign out'),
              trailing: const Icon(Icons.chevron_right),
              onTap: controller.signOut,
            ),
          ],
        ),
      ),
    ],
  );
}

class AccountAvatar extends StatefulWidget {
  const AccountAvatar({
    super.key,
    required this.controller,
    required this.profile,
    this.preview,
    this.dimension = 76,
  });
  final AccountController controller;
  final Account profile;
  final Uint8List? preview;
  final double dimension;

  @override
  State<AccountAvatar> createState() => _AccountAvatarState();
}

class _AccountAvatarState extends State<AccountAvatar> {
  late var _url = widget.controller.profilePhotoUrl(widget.profile);

  @override
  void didUpdateWidget(AccountAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.photoPath != widget.profile.photoPath) {
      _url = widget.controller.profilePhotoUrl(widget.profile);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _url,
    builder: (context, snapshot) => ProfileAvatar(
      name: widget.profile.name,
      dimension: widget.dimension,
      preview: widget.preview,
      photoUrl: snapshot.data,
    ),
  );
}

class _EditProfile extends StatefulWidget {
  const _EditProfile({required this.controller, required this.original});
  final AccountController controller;
  final Account original;

  @override
  State<_EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<_EditProfile> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.original.name);
  late final _phone = TextEditingController(text: widget.original.phone);
  Uint8List? _photo;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (picked == null || !mounted) return;
      if (await picked.length() > SupabaseAccountRepository.maxPhotoBytes) {
        throw const FormatException('Choose a photo up to 5 MB.');
      }
      final bytes = await picked.readAsBytes();
      photoUploadType(bytes);
      if (mounted) setState(() => _photo = bytes);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Could not open the photo. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.updateProfile(
        _name.text,
        _phone.text,
        photo: _photo,
      );
      if (mounted) Navigator.pop(context, true);
    } on AccountException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Could not update your profile. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        leading: widget.original.role == AccountRole.worker
            ? CurvedBackButton.forRoute(context)
            : null,
        title: const Text('Edit profile'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: AccountAvatar(
                          controller: widget.controller,
                          profile: widget.original,
                          preview: _photo,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _choosePhoto,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose profile photo'),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _name,
                        enabled: !_busy,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (value) => (value?.trim().length ?? 0) < 2
                            ? 'Enter your full name.'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _phone,
                        enabled: !_busy,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone number',
                        ),
                        validator: (value) {
                          final phone = value?.trim() ?? '';
                          return phone.isEmpty ||
                                  RegExp(r'^\+?[0-9 ()-]{8,20}$')
                                      .hasMatch(phone)
                              ? null
                              : 'Enter a valid phone number.';
                        },
                      ),
                      const SizedBox(height: 20),
                      if (_error case final error?)
                        InfoBanner(error, warning: true),
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        child: Text(_busy ? 'Please wait…' : 'Update Profile'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReadOnly extends StatelessWidget {
  const _ReadOnly({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 14)),
      ],
    ),
  );
}

class _PasswordScreen extends StatefulWidget {
  const _PasswordScreen({required this.controller});
  final AccountController controller;
  @override
  State<_PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<_PasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController(),
      _next = TextEditingController(),
      _confirm = TextEditingController();
  String? _error;
  bool _saving = false;
  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: widget.controller.account?.role == AccountRole.worker
          ? CurvedBackButton.forRoute(context)
          : null,
      title: const Text('Change password'),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Form(
              key: _form,
              child: Column(
                children: [
                  TextFormField(
                    controller: _current,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                    ),
                    validator: (v) => v == null || v.isEmpty
                        ? 'Enter your current password.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _next,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                    ),
                    validator: (v) => (v?.length ?? 0) < 8
                        ? 'Use at least 8 characters.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirm,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                    ),
                    validator: (v) =>
                        v != _next.text ? 'Passwords do not match.' : null,
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    InfoBanner(_error!, warning: true),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving
                          ? null
                          : () async {
                              if (!_form.currentState!.validate()) {
                                return;
                              }
                              setState(() {
                                _saving = true;
                                _error = null;
                              });
                              try {
                                await widget.controller.changePassword(
                                  _current.text,
                                  _next.text,
                                );
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  showMessage(context, 'Password updated.');
                                }
                              } on AccountException catch (error) {
                                if (mounted) {
                                  setState(() => _error = error.message);
                                }
                              } on Exception {
                                if (mounted) {
                                  setState(
                                    () => _error = 'Could not update your password. Try again.',
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _saving = false);
                              }
                            },
                      child: Text(_saving ? 'Updating…' : 'Update password'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
