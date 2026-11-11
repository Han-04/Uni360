import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/work_order.dart';

Color statusColor(WorkStatus status) => switch (status) {
  WorkStatus.completed => const Color(0xFF28704A),
  WorkStatus.reworkRequired => const Color(0xFF9A5C10),
  WorkStatus.rejected => const Color(0xFFB23D49),
  WorkStatus.inProgress => AppColors.teal,
  _ => const Color(0xFF506583),
};

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final WorkStatus status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: statusColor(status).withValues(alpha: .10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        color: statusColor(status),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class WorkOrderCard extends StatelessWidget {
  const WorkOrderCard({super.key, required this.order, required this.onTap});
  final WorkOrder order;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE3E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.id,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.circle,
                    size: 7,
                    color: order.priority == TaskPriority.high
                        ? const Color(0xFFBD4F54)
                        : AppColors.teal,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${order.priority.label} priority',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                order.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      order.facility.name,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusChip(order.status),
                  Text(
                    '${dateLabel(order.scheduledAt)} · ${timeLabel(order.scheduledAt)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                  if (order.isOverdue)
                    const Text(
                      'Overdue',
                      style: TextStyle(
                        color: Color(0xFFB23D49),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
