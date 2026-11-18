import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../core/widgets/curved_back_button.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common.dart';
import '../../../../shared/account/account_controller.dart';
import '../../../../shared/account/presentation/account_profile_screen.dart';
import '../../data/assigned_work_repository.dart';
import '../../data/preventive_alert_repository.dart';
import '../../../workforce/worker_profile_repository.dart';
import 'assigned_work_details.dart';

class AssignedWorkShell extends StatefulWidget {
  const AssignedWorkShell({
    super.key,
    required this.accounts,
    required this.workerId,
    required this.load,
    this.actions,
    this.alerts,
    this.workforceDetails,
    this.loadWorkerProfile,
    this.workerStatus,
  });

  final AccountController accounts;
  final String workerId;
  final AssignedWorkLoader load;
  final AssignedWorkActions? actions;
  final PreventiveAlertRepository? alerts;
  final Widget? workforceDetails, workerStatus;
  final WorkerProfileLoader? loadWorkerProfile;

  @override
  State<AssignedWorkShell> createState() => _AssignedWorkShellState();
}

class _AssignedWorkShellState extends State<AssignedWorkShell>
    with WidgetsBindingObserver {
  int _tab = 0;
  int _beforeNotifications = 0;
  DateTime? _selected;
  late Future<List<AssignedWork>> _orders;
  List<PreventiveAlert> _alerts = [];
  bool _alertsLoading = false, _alertsError = false;
  int _alertRequest = 0;
  Timer? _alertTimer;
  DateTime? get _date => _tab == 0 ? malaysiaToday() : _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _orders = widget.load(widget.workerId, _date);
    if (widget.alerts != null) {
      _reloadAlerts();
      _alertTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _reloadAlerts(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alertTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.accounts.account?.id == widget.workerId) {
      if (_tab < 2) _reload();
      _reloadAlerts();
    }
  }

  Future<void> _reload() async {
    final request = widget.load(widget.workerId, _date);
    setState(() {
      _orders = request;
    });
    try {
      await request;
    } catch (_) {
      // The task list renders the error and offers a retry.
    }
  }

  void _selectTab(int index) {
    if (index == 2 && _tab != 2) _beforeNotifications = _tab;
    setState(() => _tab = index);
    if (index < 2) _reload();
    if (index == 2) _reloadAlerts();
  }

  Future<void> _reloadAlerts() async {
    final repository = widget.alerts;
    if (repository == null || widget.accounts.account?.id != widget.workerId) {
      return;
    }
    final current = ++_alertRequest;
    if (_alerts.isEmpty) setState(() => _alertsLoading = true);
    try {
      final rows = await repository.load(widget.workerId);
      if (mounted && current == _alertRequest) {
        setState(() {
          _alerts = rows;
          _alertsError = false;
          _alertsLoading = false;
        });
      }
    } on Exception {
      if (mounted && current == _alertRequest) {
        setState(() {
          _alertsError = true;
          _alertsLoading = false;
        });
      }
    }
  }

  Future<void> _read(PreventiveAlert alert) async {
    try {
      await widget.alerts!.markRead(widget.workerId, alert.id);
      if (mounted) await _reloadAlerts();
    } on Exception {
      if (mounted) {
        showMessage(context, 'Could not mark this alert as read. Try again.');
      }
    }
  }

  Widget _notifications(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return RefreshIndicator(
      onRefresh: _reloadAlerts,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_alertsLoading || _alertsError || _alerts.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottom),
              sliver: SliverList.list(
                children: [
                  if (_alertsLoading) const LinearProgressIndicator(),
                  if (_alertsError)
                    const InfoBanner(
                      'Could not refresh notifications. Pull down to try again.',
                      warning: true,
                    ),
                  if (_alerts.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Previously',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    for (final alert in _alerts) _notificationCard(alert),
                  ],
                ],
              ),
            )
          else
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: bottom),
                child: const Center(
                  child: EmptyState(
                    title: 'No notifications yet',
                    message: 'Your notifications will appear here as soon as you receive them.',
                    illustration: Image(
                      image: AssetImage(
                        'assets/notifications/empty-mailbox.png',
                      ),
                      width: 104,
                      height: 120,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _notificationCard(PreventiveAlert alert) {
    final sender = alert.senderName ?? 'Uni360';
    final initials = sender
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    final photo = alert.senderPhotoUrl;
    final date = malaysiaTime(alert.createdAt);
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alert.read ? null : () => _read(alert),
        child: Semantics(
          label: alert.read ? null : 'Unread notification',
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: WorkerColors.tint,
                  foregroundColor: WorkerColors.deepBlue,
                  foregroundImage: photo == null ? null : NetworkImage(photo),
                  onForegroundImageError: photo == null ? null : (_, _) {},
                  child: Text(
                    initials,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              sender,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            dateLabel(date),
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                          if (!alert.read) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.circle,
                              size: 8,
                              color: WorkerColors.blue,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        alert.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(alert.message),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectDate(DateTime? date) {
    _selected = date;
    _reload();
  }

  void _moveDate(int days) {
    final date = _selected ?? malaysiaToday();
    _selectDate(DateTime(date.year, date.month, date.day + days));
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selected ?? malaysiaToday(),
      currentDate: malaysiaToday(),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (mounted && date != null) _selectDate(date);
  }

  Future<void> _open(AssignedWork order) async {
    widget.accounts.touch();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Theme(
          data: buildWorkerTheme(Theme.of(context)),
          child: AssignedWorkDetails(
            initial: order,
            workerId: widget.workerId,
            actions: widget.actions,
          ),
        ),
      ),
    );
    if (mounted && widget.actions != null) _reload();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: buildWorkerTheme(Theme.of(context)),
    child: Scaffold(
      extendBody: true,
      appBar: AppBar(
        centerTitle: _tab == 2,
        leading: _tab == 2
            ? CurvedBackButton(
                onPressed: () => _selectTab(_beforeNotifications),
              )
            : CurvedBackButton.forRoute(context),
        title: Text(
          ['Uni360', 'My work orders', 'Notifications', 'My profile'][_tab],
        ),
        actions: [
          if (_tab < 2)
            IconButton(
              tooltip: 'Refresh assigned tasks',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          if (_tab == 2 && widget.alerts != null)
            IconButton(
              tooltip: 'Refresh notifications',
              onPressed: _reloadAlerts,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Builder(
          builder: (context) => switch (_tab) {
            2 => _notifications(context),
            3 => AccountProfileScreen(
              controller: widget.accounts,
              workforceDetails: widget.workforceDetails,
              loadWorkerProfile: widget.loadWorkerProfile,
              workerStatus: widget.workerStatus,
            ),
            _ => _tasks(),
          },
        ),
      ),
      bottomNavigationBar: _footer(),
    ),
  );

  Widget _footer() {
    final unread = _alerts.any((alert) => !alert.read);
    return SafeArea(
      key: const ValueKey('worker-footer'),
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26192D48),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCFFFFFFF), Color(0xADDBE5F5)],
                ),
                border: Border.all(color: const Color(0xCFFFFFFF)),
                borderRadius: BorderRadius.circular(36),
              ),
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  height: 72,
                  child: Row(
                    children: [
                      _footerTab(0, 'Home', Icons.home_outlined),
                      _footerTab(1, 'My tasks', Icons.assignment_outlined),
                      _footerTab(
                        2,
                        'Notifications',
                        Icons.notifications_outlined,
                        unread: unread,
                      ),
                      _footerTab(3, 'Profile', Icons.person_outline),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footerTab(
    int index,
    String label,
    IconData icon, {
    bool unread = false,
  }) {
    final selected = _tab == index;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final color = selected ? WorkerColors.deepBlue : AppColors.navy;
    void onTap() => _selectTab(index);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: unread ? '$label, unread notifications' : label,
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: AnimatedContainer(
                  duration: duration,
                  constraints: const BoxConstraints(
                    minWidth: 60,
                    minHeight: 55,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  decoration: ShapeDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: selected
                          ? const [Color(0x88A1B7E4), Color(0xDCFFFFFF)]
                          : const [Colors.transparent, Colors.transparent],
                    ),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: selected
                            ? const Color(0x688195BB)
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Badge(
                        isLabelVisible: unread,
                        child: Icon(icon, size: 22, color: color),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
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
    );
  }

  Widget _homeSummary(BuildContext context, List<AssignedWork> orders) {
    final profile = widget.accounts.account;
    final completed = orders
        .where((order) => order.status == AssignedWorkStatus.completed)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profile != null)
          Row(
            children: [
              AccountAvatar(
                controller: widget.accounts,
                profile: profile,
                dimension: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hi, ${profile.name.trim().split(RegExp(r'\s+')).first}',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      dateLabel(malaysiaToday()),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 14),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [WorkerColors.blue, WorkerColors.deepBlue],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.event_available_outlined,
                  color: Colors.white,
                  size: 21,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Today’s progress',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$completed of ${orders.length} assignments completed',
                  style: const TextStyle(color: Color(0xFFE5EDFF)),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: orders.isEmpty ? 0 : completed / orders.length,
                    backgroundColor: const Color(0x55FFFFFF),
                    color: Colors.white,
                    semanticsLabel: 'Today’s task progress',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dateStrip(BuildContext context) {
    final center = _selected ?? malaysiaToday();
    final localizations = MaterialLocalizations.of(context);
    return Row(
      children: [
        for (var offset = -2; offset <= 2; offset++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _dateChip(
                localizations,
                DateTime(center.year, center.month, center.day + offset),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dateChip(MaterialLocalizations localizations, DateTime date) {
    final selected = _selected != null && sameDay(date, _selected!);
    final foreground = selected ? Colors.white : AppColors.navy;
    return Semantics(
      selected: selected,
      child: Tooltip(
        message: localizations.formatFullDate(date),
        child: TextButton(
          onPressed: () => _selectDate(date),
          style: TextButton.styleFrom(
            backgroundColor: selected ? WorkerColors.blue : Colors.white,
            foregroundColor: foreground,
            padding: const EdgeInsets.symmetric(vertical: 10),
            minimumSize: const Size(0, 56),
            shape: const StadiumBorder(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${date.day}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                const [
                  'Mon',
                  'Tue',
                  'Wed',
                  'Thu',
                  'Fri',
                  'Sat',
                  'Sun',
                ][date.weekday - 1],
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskCard(AssignedWork order) {
    final (ink, background) = switch (order.status) {
      AssignedWorkStatus.assigned => (WorkerColors.deepBlue, WorkerColors.tint),
      AssignedWorkStatus.inProgress => (
        const Color(0xFF825000),
        const Color(0xFFFFEECF),
      ),
      AssignedWorkStatus.submitted => (
        const Color(0xFF5936A9),
        const Color(0xFFF1E9FF),
      ),
      AssignedWorkStatus.completed => (
        const Color(0xFF146345),
        const Color(0xFFDDF6E9),
      ),
    };
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(order),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (order.locations.isNotEmpty)
                      Text(
                        order.locations.join(' · '),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    Text(
                      order.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      assignedWorkTime(order),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DecoratedBox(
                      decoration: ShapeDecoration(
                        color: background,
                        shape: const StadiumBorder(),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          order.status.label,
                          style: TextStyle(
                            color: ink,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: WorkerColors.blue,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Iterable<Widget> _timeline(List<AssignedWork> orders) sync* {
    DateTime? previous;
    for (final order in orders) {
      if (_selected == null &&
          (previous == null || !sameDay(previous, order.starts))) {
        yield Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
          child: Text(
            dateLabel(order.starts),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        );
      }
      previous = order.starts;
      yield Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                timeLabel(order.starts),
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ),
          Expanded(child: _taskCard(order)),
        ],
      );
    }
  }

  Widget _tasks() => FutureBuilder<List<AssignedWork>>(
    future: _orders,
    builder: (context, snapshot) {
      final orders = [...?snapshot.data]
        ..sort((a, b) => a.starts.compareTo(b.starts));
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            18,
            7,
            18,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            if (_tab == 0) ...[
              if (snapshot.connectionState == ConnectionState.done &&
                  !snapshot.hasError)
                _homeSummary(context, orders),
              SectionHeading(
                'Today’s assignments',
                action: TextButton(
                  onPressed: () => _selectTab(1),
                  child: const Text('View all tasks'),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous day',
                    onPressed: () => _moveDate(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _chooseDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 17),
                      label: Text(
                        _selected == null ? 'All dates' : dateLabel(_selected!),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next day',
                    onPressed: () => _moveDate(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  if (_selected != null)
                    IconButton(
                      tooltip: 'Show all dates',
                      onPressed: () => _selectDate(null),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _dateStrip(context),
              SectionHeading(
                _selected == null ? 'Schedule' : dateLabel(_selected!),
              ),
              const Text(
                'Malaysia time',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
            if (snapshot.connectionState != ConnectionState.done)
              const LinearProgressIndicator(
                semanticsLabel: 'Loading assigned tasks',
              )
            else if (snapshot.hasError)
              const EmptyState(
                title: 'Could not load assigned tasks',
                message: 'Refresh to try again.',
              )
            else if (orders.isEmpty)
              EmptyState(
                title: 'No assigned tasks',
                message: _date == null
                    ? 'Approved work orders will appear here.'
                    : 'There are no approved assignments for this date.',
              )
            else if (_tab == 0)
              for (final order in orders) _taskCard(order)
            else
              ..._timeline(orders),
          ],
        ),
      );
    },
  );
}
