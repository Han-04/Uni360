import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/curved_back_button.dart';
import '../../../shared/account/account.dart';
import '../../../shared/account/account_controller.dart';
import '../../../shared/account/account_repository.dart';
import 'admin_accounts.dart';
import 'admin_approvals.dart';
import 'admin_catalog.dart';
import 'admin_data.dart';
import 'admin_leave_requests.dart';
import 'admin_overdue_tasks.dart';
import 'admin_workforce.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({
    super.key,
    required this.accounts,
    required this.data,
    this.openCorrective,
  });
  final AccountController accounts;
  final AdminData data;
  final void Function(BuildContext, Account)? openCorrective;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: accounts,
    builder: (context, _) {
      final account = accounts.account;
      if (account == null) return _AdminSignIn(accounts: accounts);
      if (!account.role.isAdministrator) {
        return Scaffold(
          appBar: AppBar(
            leading: CurvedBackButton.forRoute(context),
            title: const Text('Uni360 Administration'),
          ),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'An Administrator or Super Administrator account is required.',
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: accounts.signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        );
      }
      return _Workspace(
        data: data,
        account: account,
        signOut: accounts.signOut,
        openCorrective: openCorrective,
      );
    },
  );
}

class _AdminSignIn extends StatefulWidget {
  const _AdminSignIn({required this.accounts});
  final AccountController accounts;

  @override
  State<_AdminSignIn> createState() => _AdminSignInState();
}

class _AdminSignInState extends State<_AdminSignIn> {
  final email = TextEditingController();
  final password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool hidePassword = true;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    if (widget.accounts.busy || !form.currentState!.validate()) return;
    setState(() => error = null);
    try {
      await widget.accounts.signIn(
        email.text,
        password.text,
        administratorOnly: true,
      );
    } on AccountException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Sign-in is unavailable. Try again.');
    } finally {
      if (mounted) password.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.accounts.busy;
    final message = error ?? widget.accounts.sessionMessage;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, size) {
          return Row(
            children: [
              if (size.maxWidth >= 850)
                Expanded(
                  flex: 2,
                  child: ColoredBox(
                    color: AppColors.navy,
                    child: Padding(
                      padding: const EdgeInsets.all(44),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Brand(),
                          const Spacer(),
                          const Icon(
                            Icons.shield_outlined,
                            size: 52,
                            color: Color(0xFFADE2DC),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Administration workspace',
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Manage preventive maintenance and workforce access.',
                            style: TextStyle(color: Colors.white70),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                    if (Navigator.canPop(context))
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: CurvedBackButton(),
                      ),
                    Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 64, 24, 32),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Card(
                            color: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Form(
                                key: form,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Administrator sign-in',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'Use your Uni360 Administrator or Super Administrator account.',
                                    ),
                                    const SizedBox(height: 20),
                                    TextFormField(
                                      controller: email,
                                      enabled: !busy,
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [
                                        AutofillHints.username,
                                      ],
                                      decoration: const InputDecoration(
                                        labelText: 'Email',
                                        prefixIcon: Icon(Icons.mail_outline),
                                      ),
                                      validator: (value) =>
                                          (value ?? '').contains('@')
                                          ? null
                                          : 'Enter your email.',
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: password,
                                      enabled: !busy,
                                      obscureText: hidePassword,
                                      autofillHints: const [
                                        AutofillHints.password,
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Password',
                                        prefixIcon: const Icon(
                                          Icons.lock_outline,
                                        ),
                                        suffixIcon: IconButton(
                                          tooltip: hidePassword
                                              ? 'Show password'
                                              : 'Hide password',
                                          onPressed: () => setState(
                                            () => hidePassword = !hidePassword,
                                          ),
                                          icon: Icon(
                                            hidePassword
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                          ),
                                        ),
                                      ),
                                      validator: (value) =>
                                          (value ?? '').isEmpty
                                          ? 'Enter your password.'
                                          : null,
                                      onFieldSubmitted: (_) => signIn(),
                                    ),
                                    if (message != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(
                                          message,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 18),
                                    FilledButton(
                                      onPressed: busy ? null : signIn,
                                      child: Text(
                                        busy ? 'Signing in…' : 'Sign in',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Icon(Icons.shield_outlined, color: Color(0xFFADE2DC)),
      SizedBox(width: 12),
      Text(
        'Uni360',
        style: TextStyle(
          color: Colors.white,
          fontSize: 23,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _Workspace extends StatefulWidget {
  const _Workspace({
    required this.account,
    required this.data,
    required this.signOut,
    this.openCorrective,
  });
  final Account account;
  final AdminData data;
  final VoidCallback signOut;
  final void Function(BuildContext, Account)? openCorrective;

  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  int index = 0;
  int overdueCount = 0;
  Timer? overdueTimer;
  static const labels = [
    'Account management',
    'Workforce management',
    'Facilities',
    'Schedule Task',
    'Task approvals',
    'Leave requests',
    'Overdue tasks',
  ];
  static const icons = [
    Icons.manage_accounts_outlined,
    Icons.groups_outlined,
    Icons.apartment_outlined,
    Icons.event_available_outlined,
    Icons.fact_check_outlined,
    Icons.event_busy_outlined,
    Icons.warning_amber_rounded,
  ];

  @override
  void initState() {
    super.initState();
    unawaited(refreshOverdueCount());
    overdueTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => refreshOverdueCount(),
    );
  }

  @override
  void dispose() {
    overdueTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshOverdueCount() async {
    try {
      final count = await widget.data.overdueCount();
      if (mounted && overdueCount != count) {
        setState(() => overdueCount = count);
      }
    } catch (_) {
      // Keep the last count during a temporary connection failure.
    }
  }

  Widget sidebar({required bool compact}) => Material(
    color: AppColors.navy,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 22, 16, 22),
            child: _Brand(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (var i = 0; i < labels.length; i++)
                  ListTile(
                    leading: i == 6 && overdueCount > 0
                        ? Badge.count(
                            count: overdueCount,
                            child: Icon(icons[i], color: Colors.white70),
                          )
                        : Icon(icons[i], color: Colors.white70),
                    title: Text(labels[i]),
                    textColor: Colors.white,
                    selected: i == index,
                    selectedColor: Colors.white,
                    selectedTileColor: Colors.white12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onTap: () {
                      setState(() => index = i);
                      if (i == 6) unawaited(refreshOverdueCount());
                      if (compact) Navigator.of(context).pop();
                    },
                  ),
                if (widget.openCorrective case final open?)
                  ListTile(
                    leading: const Icon(
                      Icons.handyman_outlined,
                      color: Colors.white70,
                    ),
                    title: const Text('Corrective Maintenance'),
                    textColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onTap: () {
                      if (compact) Navigator.of(context).pop();
                      open(context, widget.account);
                    },
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.account.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.account.role.label,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: widget.signOut,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.navy,
                  ),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final superAdmin = widget.account.role == AccountRole.superAdministrator;
    return LayoutBuilder(
      builder: (context, size) {
        final compact = size.maxWidth < 820;
        final padding = EdgeInsets.all(compact ? 16 : 32);
        final section = switch (index) {
          0 => AdminAccounts(data: data, superAdmin: superAdmin),
          1 => AdminWorkforce(data: data),
          2 => AdminFacilities(data: data, padding: padding),
          3 => AdminTaskTemplates(data: data, superAdmin: superAdmin),
          4 => AdminApprovals(data: data),
          5 => AdminLeaveRequests(data: data),
          _ => AdminOverdueTasks(data: data),
        };
        return Scaffold(
          appBar: AppBar(
            leading: compact ? null : CurvedBackButton.forRoute(context),
            title: const Text('Uni360 Administration'),
            actions: compact && Navigator.canPop(context)
                ? [const CurvedBackButton(tooltip: 'Back to Uni360')]
                : null,
          ),
          drawer: compact ? Drawer(child: sidebar(compact: true)) : null,
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compact)
                  SizedBox(width: 246, child: sidebar(compact: false)),
                Expanded(
                  child: index == 2
                      ? section
                      : SingleChildScrollView(
                          key: ValueKey(index),
                          padding: padding,
                          child: section,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
