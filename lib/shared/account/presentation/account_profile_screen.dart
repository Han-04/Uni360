import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../account_controller.dart';
import '../account_repository.dart';

class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({
    super.key,
    required this.controller,
    this.workforceDetails,
  });
  final AccountController controller;
  final Widget? workforceDetails;
  @override
  State<AccountProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<AccountProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.controller.account!.name,
  );
  late final _phone = TextEditingController(
    text: widget.controller.account!.phone,
  );
  bool _saving = false;
  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _password() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _PasswordScreen(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.account!;
    final initials = profile.name
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0])
        .join();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: CircleAvatar(
            radius: 38,
            backgroundColor: AppColors.teal,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            profile.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 21),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            profile.role.label,
            style: const TextStyle(color: AppColors.muted),
          ),
        ),
        const SectionHeading('Personal details'),
        Form(
          key: _form,
          child: SurfaceCard(
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  textCapitalization: TextCapitalization.words,
                  maxLength: 120,
                  validator: (v) => (v?.trim().length ?? 0) < 2
                      ? 'Enter your full name.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    final phone = value?.trim() ?? '';
                    return phone.isEmpty ||
                            RegExp(r'^\+?[0-9 ()-]{8,20}$').hasMatch(phone)
                        ? null
                        : 'Enter a valid phone number.';
                  },
                ),
                const SizedBox(height: 20),
                _ReadOnly(label: 'EMPLOYEE ID', value: profile.employeeId),
                const SizedBox(height: 16),
                _ReadOnly(label: 'EMAIL', value: profile.email),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            if (!_form.currentState!.validate()) {
                              return;
                            }
                            setState(() => _saving = true);
                            try {
                              await widget.controller.updateProfile(
                                _name.text,
                                _phone.text,
                              );
                              if (context.mounted) {
                                showMessage(context, 'Profile saved.');
                              }
                            } on AccountException catch (error) {
                              if (context.mounted) {
                                showMessage(context, error.message);
                              }
                            } on Exception {
                              if (context.mounted) {
                                showMessage(
                                  context,
                                  'Could not save your profile. Try again.',
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                    child: Text(_saving ? 'Saving…' : 'Save profile'),
                  ),
                ),
              ],
            ),
          ),
        ),
        ?widget.workforceDetails,
        const SectionHeading('Account'),
        OutlinedButton.icon(
          onPressed: _password,
          icon: const Icon(Icons.lock_outline),
          label: const Text('Change password'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => widget.controller.signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
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
    appBar: AppBar(title: const Text('Change password')),
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
