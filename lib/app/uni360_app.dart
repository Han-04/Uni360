import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/phone_viewport.dart';
import '../features/preventive/data/assigned_work_repository.dart';
import '../features/preventive/presentation/screens/assigned_work_shell.dart';
import '../features/workforce/worker_profile_repository.dart';
import '../features/workforce/worker_profile_section.dart';
import '../shared/account/account.dart';
import '../shared/account/account_controller.dart';
import '../shared/account/account_repository.dart';
import '../shared/account/presentation/login_screen.dart';
import '../shared/account/presentation/admin_portal_button.dart';
import '../shared/account/presentation/admin_portal_view.dart';

class Uni360App extends StatefulWidget {
  const Uni360App({
    super.key,
    required this.accounts,
    this.loadWorkerProfile,
    required this.loadAssignedWork,
    this.workActions,
  });
  final AccountRepository accounts;
  final WorkerProfileLoader? loadWorkerProfile;
  final AssignedWorkLoader loadAssignedWork;
  final AssignedWorkActions? workActions;
  @override
  State<Uni360App> createState() => _Uni360AppState();
}

class _Uni360AppState extends State<Uni360App> with WidgetsBindingObserver {
  late final _accounts = AccountController(widget.accounts);
  late final _adminVisible = ValueNotifier(
    kIsWeb && Uri.base.fragment == adminPortalRoute,
  );
  Timer? _sessionTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _accounts.checkSession(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _accounts.checkSession();
    }
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _accounts.dispose();
    _adminVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _accounts,
    builder: (context, _) => MaterialApp(
      key: ValueKey(_accounts.account?.id),
      title: 'Uni360',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorObservers: [
        _AdminRouteObserver((visible) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _adminVisible.value = kIsWeb && visible;
          });
        }),
      ],
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: _adminVisible,
        child: Listener(onPointerDown: (_) => _accounts.touch(), child: child!),
        builder: (context, visible, navigator) =>
            PhoneViewport(fullWidth: visible, child: navigator!),
      ),
      routes: {
        adminPortalRoute: (context) => Scaffold(
          appBar: AppBar(title: const Text('Uni360 Administration')),
          body: const SafeArea(child: AdminPortalView()),
        ),
      },
      home: _home(),
    ),
  );

  Widget _home() {
    final account = _accounts.account;
    if (account == null) return LoginScreen(controller: _accounts);
    if (account.role == AccountRole.worker) {
      final workforceDetails = switch (widget.loadWorkerProfile) {
        final load? => WorkerProfileSection(workerId: account.id, load: load),
        null => null,
      };
      return AssignedWorkShell(
        accounts: _accounts,
        workerId: account.id,
        load: widget.loadAssignedWork,
        actions: widget.workActions,
        workforceDetails: workforceDetails,
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(account.role.label)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Open the Uni360 administration portal on your computer to manage accounts.',
            ),
            const SizedBox(height: 20),
            const AdminPortalButton(),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _accounts.signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminRouteObserver extends NavigatorObserver {
  _AdminRouteObserver(this.onChanged);
  final ValueChanged<bool> onChanged;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    onChanged(topRoute.settings.name == adminPortalRoute);
  }
}
