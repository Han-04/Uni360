import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WorkerCalendarDialog extends StatefulWidget {
  const WorkerCalendarDialog({
    super.key,
    required this.title,
    required this.today,
    required this.selected,
    required this.firstDate,
    required this.lastDate,
    this.markers = const {},
    this.footer,
  });

  final String title;
  final DateTime today, firstDate, lastDate;
  final DateTime? selected;
  final Map<DateTime, ({Color color, String label})> markers;
  final Widget? footer;

  @override
  State<WorkerCalendarDialog> createState() => _WorkerCalendarDialogState();
}

class _WorkerCalendarDialogState extends State<WorkerCalendarDialog> {
  late DateTime month = DateUtils.addMonthsToMonthDate(
    widget.selected ?? widget.today,
    0,
  );

  void move(int offset) => setState(() {
    month = DateUtils.addMonthsToMonthDate(month, offset);
  });

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final offset = month.weekday - 1;
    final count = DateUtils.getDaysInMonth(month.year, month.month);
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close calendar',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed:
                        month.isAfter(
                          DateUtils.addMonthsToMonthDate(widget.firstDate, 0),
                        )
                        ? () => move(-1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        localizations.formatMonthYear(month),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed:
                        month.isBefore(
                          DateUtils.addMonthsToMonthDate(widget.lastDate, 0),
                        )
                        ? () => move(1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Table(
                children: [
                  TableRow(
                    children: [
                      for (final day in const [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ])
                        Center(
                          child: Text(
                            day,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (var row = 0; row < (offset + count + 6) ~/ 7; row++)
                    TableRow(
                      children: [
                        for (var column = 0; column < 7; column++)
                          if (row * 7 + column - offset + 1 case final day
                              when day >= 1 && day <= count)
                            _dayButton(
                              context,
                              DateTime(month.year, month.month, day),
                            )
                          else
                            const SizedBox(height: 44),
                      ],
                    ),
                ],
              ),
              if (widget.footer case final footer?) ...[
                const Divider(height: 22),
                footer,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayButton(BuildContext context, DateTime date) {
    final selected = DateUtils.isSameDay(date, widget.selected);
    final selectable =
        !date.isBefore(widget.firstDate) && !date.isAfter(widget.lastDate);
    final marker = widget.markers[date];
    final label = MaterialLocalizations.of(context).formatFullDate(date);
    return Semantics(
      selected: selected,
      child: Tooltip(
        message: marker == null ? label : '$label · ${marker.label}',
        child: TextButton(
          onPressed: selectable ? () => Navigator.pop(context, date) : null,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: EdgeInsets.zero,
            foregroundColor: selected ? Colors.white : AppColors.navy,
            backgroundColor: selected ? WorkerColors.blue : null,
            side: DateUtils.isSameDay(date, widget.today) && !selected
                ? const BorderSide(color: WorkerColors.blue)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${date.day}'),
              if (marker != null)
                Icon(Icons.circle, size: 6, color: marker.color)
              else
                const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}
