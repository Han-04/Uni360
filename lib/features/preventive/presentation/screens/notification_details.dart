import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/curved_back_button.dart';
import '../../data/assigned_work_repository.dart';
import '../../data/preventive_alert_repository.dart';

class NotificationDetails extends StatelessWidget {
  const NotificationDetails({super.key, required this.notification});

  final PreventiveAlert notification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = malaysiaTime(notification.createdAt);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: const CurvedBackButton(),
        title: const Text('Notification'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(
                    color: WorkerColors.tint,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          NotificationAvatar(
                            notification: notification,
                            radius: 23,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  notification.senderName ?? 'Uni360',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${dateLabel(date)} · ${timeLabel(date)} MYT',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          notification.message,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationAvatar extends StatelessWidget {
  const NotificationAvatar({
    super.key,
    required this.notification,
    this.radius = 18,
  });

  final PreventiveAlert notification;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = (notification.senderName ?? 'Uni360')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    final photo = notification.senderPhotoUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: WorkerColors.tint,
      foregroundColor: WorkerColors.deepBlue,
      foregroundImage: photo == null ? null : NetworkImage(photo),
      onForegroundImageError: photo == null ? null : (_, _) {},
      child: Text(
        initials,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
