import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/phone_viewport.dart';
import '../features/corrective/corrective_access.dart';
import '../features/corrective/corrective_admin.dart';
import '../features/corrective/corrective_repository.dart';
import '../features/preventive/admin/admin_dashboard.dart';
import '../features/preventive/admin/admin_data.dart';
import '../features/preventive/data/assigned_work_repository.dart';
import '../features/preventive/data/preventive_alert_repository.dart';
import '../features/preventive/presentation/screens/assigned_work_shell.dart';
import '../features/workforce/worker_profile_repository.dart';
import '../features/workforce/worker_leave_repository.dart';
import '../features/workforce/worker_leave_screen.dart';
import '../features/workforce/worker_status_badge.dart';
import '../shared/account/account.dart';
import '../shared/account/account_controller.dart';
import '../shared/account/account_repository.dart';
import '../shared/account/presentation/login_screen.dart';
import '../shared/account/presentation/admin_portal_button.dart';
import 'campus_workspace.dart';

class Uni360App extends StatefulWidget {
  const Uni360App({
    super.key,
    required this.accounts,
    this.loadWorkerProfile,
    required this.loadAssignedWork,
    this.workActions,
    this.corrective,
    this.administration,
    this.alerts,
    this.leave,
    this.initialRecovery = false,
  });
  final AccountRepository accounts;
  final WorkerProfileLoader? loadWorkerProfile;
  final AssignedWorkLoader loadAssignedWork;
  final AssignedWorkActions? workActions;
  final CorrectiveRepository? corrective;
  final AdminData? administration;
  final PreventiveAlertRepository? alerts;
  final WorkerLeaveRepository? leave;
  final bool initialRecovery;
  @override
  State<Uni360App> createState() => _Uni360AppState();
}

class _Uni360AppState extends State<Uni360App> with WidgetsBindingObserver {
  late final _accounts = AccountController(widget.accounts);
  late final _adminVisible = ValueNotifier(
    widget.administration != null && Uri.base.fragment == adminPortalRoute,
  );
  Timer? _sessionTimer;
  StreamSubscription<AuthState>? _recoverySubscription;
  late bool _recovering = widget.initialRecovery;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recoverySubscription = widget.corrective?.client.auth.onAuthStateChange
        .listen((state) {
          if (mounted && state.event == AuthChangeEvent.passwordRecovery) {
            setState(() => _recovering = true);
          }
        });
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
    unawaited(_recoverySubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _accounts.dispose();
    _adminVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _accounts,
    builder: (context, _) => MaterialApp(
      key: ValueKey(
        _recovering ? 'corrective-recovery' : _accounts.account?.id,
      ),
      title: 'Uni360',
      initialRoute: _adminVisible.value ? adminPortalRoute : null,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorObservers: [
        _AdminRouteObserver((visible) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _adminVisible.value = widget.administration != null && visible;
            }
          });
        }),
      ],
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: _adminVisible,
        child: Listener(onPointerDown: (_) => _accounts.touch(), child: child!),
        builder: (context, visible, navigator) => PhoneViewport(
          fullWidth:
              visible ||
              (kIsWeb &&
                  widget.corrective != null &&
                  _accounts.account?.role.isAdministrator == true),
          child: navigator!,
        ),
      ),
      routes: {
        adminPortalRoute: (context) {
          final data = widget.administration;
          if (data == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Uni360 Administration')),
              body: const Center(
                child: Text(
                  'Open Uni360 in a desktop browser to manage accounts.',
                ),
              ),
            );
          }
          return AdminDashboard(accounts: _accounts, data: data);
        },
        correctiveAdminRoute: (context) {
          final account = _accounts.account;
          final repository = widget.corrective;
          if (account == null ||
              !account.role.isAdministrator ||
              repository == null) {
            return _home();
          }
          return CorrectiveAdmin(repository: repository, account: account);
        },
      },
      home: _home(),
    ),
  );

  Widget _home() {
    final account = _accounts.account;
    final corrective = widget.corrective;
    if (_recovering && corrective != null) {
      return CorrectivePasswordResetScreen(
        client: corrective.client,
        onDone: () => setState(() => _recovering = false),
      );
    }
    if (account == null) {
      return LoginScreen(
        controller: _accounts,
        openAccess: corrective == null
            ? null
            : (context, register) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CorrectiveAccessScreen(
                      client: corrective.client,
                      register: register,
                    ),
                  ),
                );
              },
      );
    }
    if (account.role == AccountRole.worker) {
      final workerStatus = switch (widget.leave) {
        final repository? => WorkerStatusBadge(
          workerId: account.id,
          repository: repository,
        ),
        null => null,
      };
      final workforceDetails = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.leave case final repository?)
            WorkerLeaveEntry(workerId: account.id, repository: repository),
        ],
      );
      final preventive = AssignedWorkShell(
        accounts: _accounts,
        workerId: account.id,
        load: widget.loadAssignedWork,
        actions: widget.workActions,
        alerts: widget.alerts,
        workforceDetails: workforceDetails,
        loadWorkerProfile: widget.loadWorkerProfile,
        workerStatus: workerStatus,
      );
      final corrective = widget.corrective;
      if (corrective == null) return preventive;
      return CampusWorkspace(
        accounts: _accounts,
        account: account,
        corrective: corrective,
        preventive: preventive,
        workforceDetails: workforceDetails,
        loadWorkerProfile: widget.loadWorkerProfile,
        workerStatus: workerStatus,
      );
    }
    if (widget.corrective case final corrective?) {
      return CampusWorkspace(
        accounts: _accounts,
        account: account,
        corrective: corrective,
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
    if (topRoute is PageRoute) {
      onChanged(topRoute.settings.name == adminPortalRoute);
    }
  }
}
