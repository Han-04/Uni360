import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/curved_back_button.dart';
import '../features/corrective/corrective_admin.dart';
import '../features/corrective/corrective_mobile.dart';
import '../features/corrective/corrective_repository.dart';
import '../features/corrective/corrective_widgets.dart';
import '../features/workforce/worker_profile_repository.dart';
import '../shared/account/account.dart';
import '../shared/account/account_controller.dart';
import '../shared/account/presentation/account_profile_screen.dart';
import '../shared/account/presentation/admin_portal_button.dart';

class CampusWorkspace extends StatefulWidget {
  const CampusWorkspace({
    super.key,
    required this.accounts,
    required this.account,
    required this.corrective,
    this.preventive,
    this.workforceDetails,
    this.loadWorkerProfile,
    this.workerStatus,
  });
  final AccountController accounts;
  final Account account;
  final CorrectiveRepository corrective;
  final Widget? preventive, workforceDetails, workerStatus;
  final WorkerProfileLoader? loadWorkerProfile;

  @override
  State<CampusWorkspace> createState() => _CampusWorkspaceState();
}

class _CampusWorkspaceState extends State<CampusWorkspace> {
  RealtimeChannel? _channel;
  Future<int>? _updates;
  bool get _worker => widget.account.role == AccountRole.worker;
  bool get _reporter => widget.account.role == AccountRole.reporter;

  @override
  void initState() {
    super.initState();
    if (!widget.account.role.isAdministrator) {
      _updates = widget.corrective.unreadNotifications();
      _channel = widget.corrective.watch('workspace', _reload);
    }
  }

  @override
  void dispose() {
    if (_channel case final channel?) {
      unawaited(widget.corrective.unwatch(channel));
    }
    super.dispose();
  }

  void _reload() {
    if (mounted && !widget.account.role.isAdministrator) {
      setState(() {
        _updates = widget.corrective.unreadNotifications();
      });
    }
  }

  Future<void> _corrective({int tab = 0}) async {
    if (widget.account.role.isAdministrator) {
      await Navigator.of(context).pushNamed(correctiveAdminRoute);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CorrectiveMobile(
          repository: widget.corrective,
          account: widget.account,
          initialTab: _reporter && tab == 0 ? 1 : tab,
        ),
      ),
    );
    _reload();
  }

  Future<void> _preventive() async {
    if (_worker) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => widget.preventive!));
    } else {
      await Navigator.of(context).pushNamed(adminPortalRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.account.name.trim().split(RegExp(r'\s+')).first;
    final modules = [
      _ModuleTile(
        title: 'Corrective Maintenance',
        description: _reporter
            ? 'Report a campus fault and track your requests.'
            : _worker
            ? 'Report a fault, respond to an assignment or track a repair.'
            : 'Verify incidents, dispatch workers and review repair evidence.',
        icon: Icons.handyman_outlined,
        color: correctiveAccent,
        tint: correctiveTint,
        onOpen: _corrective,
      ),
      if (!_reporter)
        _ModuleTile(
          title: 'Preventive Maintenance',
          description: _worker
              ? 'View scheduled inspections, servicing and campus tasks.'
              : 'Open the administration portal for facilities, schedules and task approvals.',
          icon: Icons.event_available_outlined,
          color: AppColors.teal,
          tint: const Color(0xFFE5F4EF),
          onOpen: _worker || kIsWeb ? _preventive : null,
          disabledLabel:
              'Open Uni360 on a computer to manage preventive schedules.',
        ),
    ];
    final workspace = Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_outlined,
              color: _worker ? WorkerColors.blue : AppColors.teal,
            ),
            const SizedBox(width: 8),
            const Text('Uni360', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'My profile',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(
                    leading: _worker ? const CurvedBackButton() : null,
                    title: const Text('My profile'),
                    backgroundColor: _worker ? WorkerColors.background : null,
                  ),
                  body: AccountProfileScreen(
                    controller: widget.accounts,
                    workforceDetails: widget.workforceDetails,
                    loadWorkerProfile: widget.loadWorkerProfile,
                    workerStatus: widget.workerStatus,
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: widget.accounts.signOut,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1060),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 740;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 32 : 20,
                    12,
                    wide ? 32 : 20,
                    30,
                  ),
                  children: [
                    CorrectiveHero(
                      title: 'Campus operations',
                      subtitle: 'Welcome, $name · ${widget.account.role.label}',
                      icon: Icons.apartment_rounded,
                      gradientColors: _worker
                          ? const [WorkerColors.blue, WorkerColors.deepBlue]
                          : const [Color(0xFF10243D), Color(0xFF154D59)],
                    ),
                    correctiveGap(22),
                    if (!widget.account.role.isAdministrator)
                      FutureBuilder(
                        future: _updates,
                        builder: (context, snapshot) {
                          final actionable = snapshot.data ?? 0;
                          if (actionable == 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: FilledButton.icon(
                              onPressed: () => _corrective(tab: 2),
                              icon: const Icon(
                                Icons.notifications_active_outlined,
                              ),
                              label: Text(
                                '$actionable unread corrective update${actionable == 1 ? '' : 's'}',
                              ),
                            ),
                          );
                        },
                      ),
                    const CorrectiveHeading('Maintenance workspaces'),
                    correctiveGap(),
                    if (wide && modules.length == 2)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: modules[0]),
                          const SizedBox(width: 14),
                          Expanded(child: modules[1]),
                        ],
                      )
                    else ...[
                      modules[0],
                      correctiveGap(),
                      if (modules.length == 2) modules[1],
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    return _worker
        ? Theme(data: buildWorkerTheme(Theme.of(context)), child: workspace)
        : workspace;
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.tint,
    this.onOpen,
    this.disabledLabel,
  });
  final String title, description;
  final String? disabledLabel;
  final IconData icon;
  final Color color, tint;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFE0E6EE)),
    ),
    child: InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  correctiveGap(5),
                  Text(
                    onOpen == null ? disabledLabel ?? description : description,
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (onOpen != null)
              const Padding(
                padding: EdgeInsets.only(top: 7, left: 3),
                child: Icon(Icons.chevron_right),
              ),
          ],
        ),
      ),
    ),
  );
}
