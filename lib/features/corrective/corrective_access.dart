import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'corrective_widgets.dart';

final _campusEmail = RegExp(
  r'^[^@\s]+@(student\.)?tarc\.edu\.my$',
  caseSensitive: false,
);
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _campusId = RegExp(r'^[A-Z0-9-]{3,40}$');
const _recoveryFlag = 'uni360_recovery';

Uri get correctiveRecoveryUri => kIsWeb
    ? Uri(
        scheme: Uri.base.scheme,
        host: Uri.base.host,
        port: Uri.base.port,
        path: Uri.base.path,
        queryParameters: {_recoveryFlag: '1'},
      )
    : Uri.parse('com.example.uni360://auth/callback?$_recoveryFlag=1');

bool isCorrectiveRecoveryUri(Uri uri) {
  final expected = correctiveRecoveryUri;
  return uri.scheme == expected.scheme &&
      uri.host == expected.host &&
      uri.port == expected.port &&
      uri.path == expected.path &&
      uri.queryParameters[_recoveryFlag] == '1';
}

class CorrectiveAccessScreen extends StatefulWidget {
  const CorrectiveAccessScreen({
    super.key,
    required this.client,
    required this.register,
  });
  final SupabaseClient client;
  final bool register;

  @override
  State<CorrectiveAccessScreen> createState() => _CorrectiveAccessScreenState();
}

class _CorrectiveAccessScreenState extends State<CorrectiveAccessScreen> {
  final _form = GlobalKey<FormState>();
  final _emailField = TextEditingController();
  final _name = TextEditingController();
  final _id = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _emailField.dispose();
    _name.dispose();
    _id.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final email = _emailField.text.trim().toLowerCase();
      if (widget.register) {
        final response = await widget.client.auth.signUp(
          email: email,
          password: _password.text,
          data: {
            'uni360_role': 'reporter',
            'campus_id': _id.text.trim().toUpperCase(),
            'full_name': _name.text.trim(),
          },
        );
        if (response.session != null) {
          await widget.client.auth.signOut(scope: SignOutScope.local);
        }
        if (mounted) {
          setState(
            () => _notice = 'Check your campus email for confirmation, then return to sign in.',
          );
        }
      } else {
        await widget.client.auth.resetPasswordForEmail(
          email,
          redirectTo: correctiveRecoveryUri.toString(),
        );
        if (mounted) {
          setState(
            () => _notice = 'If this email has an account, open its recovery link on this device.',
          );
        }
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(
          () => _notice = switch (error.code) {
            'weak_password' => 'Choose a stronger password.',
            'over_email_send_rate_limit' =>
              'An email was requested recently. Try again later.',
            'signup_disabled' =>
              'Reporter registration is temporarily unavailable.',
            _ => 'The request could not be completed. Check your details and try again.',
          },
        );
      }
    } on Exception {
      if (mounted) {
        setState(
          () => _notice = 'The request could not be completed. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.register ? 'Create a reporter account' : 'Forgot password',
      ),
    ),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            CorrectiveHero(
              title: widget.register
                  ? 'Report campus faults'
                  : 'Recover your account',
              subtitle: widget.register
                  ? 'Use your TAR UMT email to register as a campus reporter.'
                  : 'Enter the email associated with your Uni360 account.',
              icon: widget.register ? Icons.person_add_alt : Icons.lock_reset,
            ),
            correctiveGap(20),
            if (widget.register) ...[
              TextFormField(
                controller: _name,
                enabled: !_busy,
                maxLength: 120,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (value) =>
                    (value?.trim().length ?? 0) < 2 ? 'Enter your name.' : null,
              ),
              TextFormField(
                controller: _id,
                enabled: !_busy,
                maxLength: 40,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Student or staff ID',
                ),
                validator: (value) =>
                    _campusId.hasMatch(value?.trim().toUpperCase() ?? '')
                    ? null
                    : 'Enter a valid campus ID.',
              ),
            ],
            TextFormField(
              controller: _emailField,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: widget.register ? 'TAR UMT email' : 'Email',
              ),
              validator: (value) =>
                  (widget.register ? _campusEmail : _email).hasMatch(
                    value?.trim() ?? '',
                  )
                  ? null
                  : (widget.register
                        ? 'Enter your TAR UMT email.'
                        : 'Enter your email.'),
            ),
            if (widget.register) ...[
              correctiveGap(),
              TextFormField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                maxLength: 72,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (value) => (value?.length ?? 0) < 8
                    ? 'Use at least eight characters.'
                    : null,
              ),
            ],
            correctiveGap(18),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(
                _busy
                    ? 'Please wait'
                    : widget.register
                    ? 'Create account'
                    : 'Send recovery link',
              ),
            ),
            if (_notice case final notice?) ...[
              correctiveGap(),
              CorrectiveMessage(notice),
            ],
          ],
        ),
      ),
    ),
  );
}

class CorrectivePasswordResetScreen extends StatefulWidget {
  const CorrectivePasswordResetScreen({
    super.key,
    required this.client,
    required this.onDone,
  });
  final SupabaseClient client;
  final VoidCallback onDone;

  @override
  State<CorrectivePasswordResetScreen> createState() =>
      _CorrectivePasswordResetScreenState();
}

class _CorrectivePasswordResetScreenState
    extends State<CorrectivePasswordResetScreen> {
  final _key = GlobalKey<FormState>();
  final _new = TextEditingController();
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_key.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await widget.client.auth.updateUser(UserAttributes(password: _new.text));
      await widget.client.auth.signOut(scope: SignOutScope.local);
      if (mounted) widget.onDone();
    } on Exception {
      if (mounted) {
        setState(() {
          _notice = 'The password could not be updated. Open a fresh recovery link if this one has expired.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Set a new password')),
    body: SafeArea(
      child: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _new,
              enabled: !_busy,
              obscureText: true,
              maxLength: 72,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: (value) => (value?.length ?? 0) < 8
                  ? 'Use at least eight characters.'
                  : null,
            ),
            TextFormField(
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Repeat new password',
              ),
              validator: (value) =>
                  value == _new.text ? null : 'The passwords must match.',
            ),
            correctiveGap(),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving' : 'Update password'),
            ),
            if (_notice case final notice?) ...[
              correctiveGap(),
              CorrectiveMessage(notice),
            ],
          ],
        ),
      ),
    ),
  );
}
