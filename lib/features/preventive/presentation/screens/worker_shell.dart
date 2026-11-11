import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common.dart';
import '../../../../shared/account/presentation/account_profile_screen.dart';
import '../../application/preventive_controller.dart';
import '../../domain/work_order.dart';
import '../widgets/work_order_card.dart';
import 'work_order_screen.dart';

class WorkerShell extends StatefulWidget {
  const WorkerShell({
    super.key,
    required this.controller,
    this.workforceDetails,
  });
  final PreventiveController controller;
  final Widget? workforceDetails;
  @override
  State<WorkerShell> createState() => _WorkerShellState();
}

class _WorkerShellState extends State<WorkerShell> {
  int _index = 0;
  void _open(WorkOrder order) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          WorkOrderScreen(controller: widget.controller, order: order),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(
          ['Uni360', 'My work orders', 'Notifications', 'My profile'][_index],
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 20),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'DEMO',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.teal,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: IndexedStack(
              index: _index,
              children: [
                _Dashboard(
                  controller: widget.controller,
                  open: _open,
                  viewAll: () => setState(() => _index = 1),
                ),
                _TaskList(controller: widget.controller, open: _open),
                _Notifications(controller: widget.controller, open: _open),
                AccountProfileScreen(
                  controller: widget.controller.accounts,
                  workforceDetails: widget.workforceDetails,
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'My tasks',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: widget.controller.unreadCount > 0,
              label: Text('${widget.controller.unreadCount}'),
              child: const Icon(Icons.notifications_outlined),
            ),
            label: 'Alerts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    ),
  );
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.controller,
    required this.open,
    required this.viewAll,
  });
  final PreventiveController controller;
  final ValueChanged<WorkOrder> open;
  final VoidCallback viewAll;
  @override
  Widget build(BuildContext context) {
    final orders = controller.orders;
    final today = orders
        .where((o) => sameDay(o.scheduledAt, DateTime.now()))
        .toList();
    final attention = orders
        .where(
          (o) =>
              o.status == WorkStatus.reworkRequired ||
              (o.priority == TaskPriority.high &&
                  [
                    WorkStatus.assigned,
                    WorkStatus.inProgress,
                  ].contains(o.status)),
        )
        .toList();
    final upcoming =
        orders.where((o) => o.status == WorkStatus.assigned).toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.wb_sunny_outlined,
                    size: 16,
                    color: Color(0xFF91D6CC),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dateLabel(DateTime.now()),
                      style: const TextStyle(
                        color: Color(0xFFBDD0E1),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Text(
                    'FIELD WORKER',
                    style: TextStyle(
                      color: Color(0xFF91D6CC),
                      fontSize: 9,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Welcome back,',
                style: TextStyle(color: Color(0xFFBDD0E1), fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                controller.accounts.account!.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${today.length} planned ${today.length == 1 ? 'task' : 'tasks'} today. Let’s keep campus running.',
                style: const TextStyle(color: Color(0xFFBDD0E1), height: 1.5),
              ),
            ],
          ),
        ),
        const SectionHeading('Your workload'),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final status in [
                WorkStatus.assigned,
                WorkStatus.inProgress,
                WorkStatus.evidenceSubmitted,
                WorkStatus.completed,
              ])
                SizedBox(
                  width: (constraints.maxWidth - 12) / 2,
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              switch (status) {
                                WorkStatus.assigned =>
                                  Icons.assignment_outlined,
                                WorkStatus.inProgress => Icons.timelapse,
                                WorkStatus.evidenceSubmitted =>
                                  Icons.fact_check_outlined,
                                _ => Icons.check_circle_outline,
                              },
                              size: 19,
                              color: statusColor(status),
                            ),
                            const Spacer(),
                            Text(
                              '${orders.where((o) => o.status == status).length}',
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          status.label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (attention.isNotEmpty) ...[
          SectionHeading(
            'Needs your attention',
            action: Text(
              '${attention.length}',
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          ...attention.map(
            (o) => WorkOrderCard(order: o, onTap: () => open(o)),
          ),
        ],
        SectionHeading(
          'Scheduled work',
          action: TextButton(onPressed: viewAll, child: const Text('View all')),
        ),
        if (upcoming.isEmpty)
          const EmptyState(
            title: 'You’re all caught up',
            message: 'New assigned tasks will appear here.',
          )
        else
          ...upcoming
              .take(3)
              .map((o) => WorkOrderCard(order: o, onTap: () => open(o))),
        const SizedBox(height: 12),
        const InfoBanner(
          'Preventive maintenance demo · Changes are kept for this app session. Device verification and photos are simulated.',
        ),
      ],
    );
  }
}

class _TaskList extends StatefulWidget {
  const _TaskList({required this.controller, required this.open});
  final PreventiveController controller;
  final ValueChanged<WorkOrder> open;
  @override
  State<_TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<_TaskList> {
  String _query = '', _period = 'All';
  WorkStatus? _status;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final filtered = widget.controller.orders.where((o) {
      final matches =
          '${o.id} ${o.title} ${o.facility.name} ${o.facility.assetTag}'
              .toLowerCase()
              .contains(_query.toLowerCase());
      final period = switch (_period) {
        'Today' => sameDay(o.scheduledAt, now),
        'Upcoming' => o.scheduledAt.isAfter(
          DateTime(now.year, now.month, now.day + 1),
        ),
        'History' => [
          WorkStatus.completed,
          WorkStatus.rejected,
          WorkStatus.evidenceSubmitted,
        ].contains(o.status),
        _ => true,
      };
      return matches && period && (_status == null || o.status == _status);
    }).toList()..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Plan your work. Track every step.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            labelText: 'Search tasks, facilities or assets',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final period in ['All', 'Today', 'Upcoming', 'History'])
              ChoiceChip(
                label: Text(period),
                selected: _period == period,
                onSelected: (_) => setState(() => _period = period),
              ),
          ],
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<WorkStatus>(
          isExpanded: true,
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Status'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Any status')),
            ...WorkStatus.values.map(
              (s) => DropdownMenuItem(value: s, child: Text(s.label)),
            ),
          ],
          onChanged: (v) => setState(() => _status = v),
        ),
        const SizedBox(height: 20),
        Text(
          '${filtered.length} work ${filtered.length == 1 ? 'order' : 'orders'}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const EmptyState(
            title: 'No work orders found',
            message: 'Try another search or adjust your filters.',
          )
        else
          ...filtered.map(
            (o) => WorkOrderCard(order: o, onTap: () => widget.open(o)),
          ),
      ],
    );
  }
}

class _Notifications extends StatelessWidget {
  const _Notifications({required this.controller, required this.open});
  final PreventiveController controller;
  final ValueChanged<WorkOrder> open;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '${controller.unreadCount} unread',
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          TextButton(
            onPressed: controller.unreadCount == 0
                ? null
                : controller.markAllRead,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (controller.notifications.isEmpty)
        const EmptyState(
          title: 'Nothing new yet',
          message: 'Assignment and review updates will appear here.',
          icon: Icons.notifications_none,
        ),
      ...controller.notifications.map(
        (n) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                controller.markRead(n);
                final linked = controller.orders.where(
                  (o) => o.id == n.workOrderId,
                );
                if (linked.isNotEmpty) {
                  open(linked.first);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFE7F4F2),
                      child: Icon(
                        n.read
                            ? Icons.notifications_none
                            : Icons.notifications_active_outlined,
                        color: AppColors.teal,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.title,
                            style: TextStyle(
                              fontWeight: n.read
                                  ? FontWeight.w500
                                  : FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            n.message,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${dateLabel(n.at)} · ${timeLabel(n.at)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!n.read)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.circle,
                          size: 8,
                          color: AppColors.teal,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
