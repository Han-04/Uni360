import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../account_controller.dart';
import '../account_repository.dart';
import 'admin_portal_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});
  final AccountController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (widget.controller.busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    try {
      await widget.controller.signIn(_email.text, _password.text);
    } on AccountException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error = 'Could not load your account. Try again or contact your administrator.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final busy = widget.controller.busy;
      final message = _error ?? widget.controller.sessionMessage;
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.navy,
                          child: Icon(
                            Icons.shield_outlined,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Uni360',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Sign in to your account',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Use the email and password assigned to your Uni360 account.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _email,
                        enabled: !busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (value) =>
                            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(value?.trim() ?? '')
                            ? null
                            : 'Enter a valid email address.',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        enabled: !busy,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter your password.'
                            : null,
                      ),
                      const SizedBox(height: 20),
                      if (message != null) ...[
                        InfoBanner(message, warning: true),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        onPressed: busy ? null : _login,
                        child: Text(busy ? 'Please wait…' : 'Sign in'),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Forgot your password? Contact your administrator.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 24),
                      const AdminPortalButton(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
