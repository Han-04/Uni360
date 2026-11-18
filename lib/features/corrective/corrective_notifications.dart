import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'corrective_repository.dart';
import 'corrective_widgets.dart';

class CorrectiveNotifications extends StatefulWidget {
  const CorrectiveNotifications({
    super.key,
    required this.repository,
    required this.openIncident,
    this.scrollable = false,
    this.emptyState,
  });
  final CorrectiveRepository repository;
  final ValueChanged<String> openIncident;
  final bool scrollable;
  final Widget? emptyState;

  @override
  State<CorrectiveNotifications> createState() =>
      _CorrectiveNotificationsState();
}

class _CorrectiveNotificationsState extends State<CorrectiveNotifications> {
  late Future<List<CorrectiveRow>> _updates;
  late final RealtimeChannel _channel;

  @override
  void initState() {
    super.initState();
    _updates = widget.repository.notifications();
    _channel = widget.repository.watch('notifications', _refresh);
  }

  @override
  void dispose() {
    unawaited(widget.repository.unwatch(_channel));
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _updates = widget.repository.notifications();
    });
  }

  Future<void> _open(CorrectiveRow notification) async {
    try {
      await widget.repository.markRead(notification['id'] as int);
      if (!mounted) return;
      _refresh();
      if (!{
        'Assignment transferred',
        'Assignment withdrawn',
      }.contains(notification['title'])) {
        widget.openIncident(notification['incident_id'] as String);
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(correctiveError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _updates,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return CorrectiveMessage(
          correctiveError(snapshot.error!),
          onRetry: _refresh,
        );
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final notifications = snapshot.data!;
      if (notifications.isEmpty) {
        return widget.emptyState ??
            const CorrectiveMessage(
              'Incident and assignment updates will appear here.',
            );
      }
      final items = [
        for (final update in notifications)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CorrectivePanel(
              padding: EdgeInsets.zero,
              child: ListTile(
                onTap: () => _open(update),
                leading: Icon(
                  update['read_at'] == null
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none,
                ),
                title: Text(
                  update['title'] as String,
                  style: TextStyle(
                    fontWeight: update['read_at'] == null
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  '${update['incident_title']}\n${correctiveTime(DateTime.parse(update['created_at'] as String))}',
                ),
              ),
            ),
          ),
      ];
      return widget.scrollable
          ? ListView(shrinkWrap: true, children: items)
          : Column(children: items);
    },
  );
}
