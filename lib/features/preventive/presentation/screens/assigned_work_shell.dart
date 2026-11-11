import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common.dart';
import '../../../../shared/account/account_controller.dart';
import '../../../../shared/account/presentation/account_profile_screen.dart';
import '../../data/assigned_work_repository.dart';
import 'assigned_work_details.dart';

class AssignedWorkShell extends StatefulWidget {
  const AssignedWorkShell({
    super.key,
    required this.accounts,
    required this.workerId,
    required this.load,
    this.actions,
    this.workforceDetails,
  });

  final AccountController accounts;
  final String workerId;
  final AssignedWorkLoader load;
  final AssignedWorkActions? actions;
  final Widget? workforceDetails;

  @override
  State<AssignedWorkShell> createState() => _AssignedWorkShellState();
}

class _AssignedWorkShellState extends State<AssignedWorkShell>
    with WidgetsBindingObserver {
  int _tab = 0;
  DateTime? _selected;
  late Future<List<AssignedWork>> _orders;
  DateTime? get _date => _tab == 0 ? malaysiaToday() : _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _orders = widget.load(widget.workerId, _date);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _tab < 2 &&
        widget.accounts.account?.id == widget.workerId) {
      _reload();
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
    setState(() => _tab = index);
    if (index < 2) _reload();
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
        builder: (_) => AssignedWorkDetails(
          initial: order,
          workerId: widget.workerId,
          actions: widget.actions,
        ),
      ),
    );
    if (mounted && widget.actions != null) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
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
      ],
    ),
    body: SafeArea(
      child: switch (_tab) {
        2 => const EmptyState(
          title: 'Nothing new yet',
          message: 'Check My tasks for approved work orders.',
          icon: Icons.notifications_none,
        ),
        3 => AccountProfileScreen(
          controller: widget.accounts,
          workforceDetails: widget.workforceDetails,
        ),
        _ => _tasks(),
      },
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: _selectTab,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
        NavigationDestination(
          icon: Icon(Icons.assignment_outlined),
          label: 'My tasks',
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_outlined),
          label: 'Alerts',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    ),
  );

  Widget _tasks() => FutureBuilder<List<AssignedWork>>(
    future: _orders,
    builder: (context, snapshot) {
      final orders = snapshot.data ?? const <AssignedWork>[];
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            if (_tab == 0)
              SectionHeading(
                'Today’s assignments',
                action: TextButton(
                  onPressed: () => _selectTab(1),
                  child: const Text('View all tasks'),
                ),
              )
            else
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
            if (_tab == 0) Text(dateLabel(malaysiaToday())),
            const Text('Malaysia time'),
            const SizedBox(height: 16),
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
            else
              for (final order in orders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SurfaceCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      onTap: () => _open(order),
                      title: Text(order.title),
                      subtitle: Text(
                        [
                          ...order.locations,
                          '${dateLabel(order.starts)} · ${assignedWorkTime(order)}',
                          order.status.label,
                        ].join('\n'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                ),
          ],
        ),
      );
    },
  );
}
