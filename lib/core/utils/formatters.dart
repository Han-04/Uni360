String timeLabel(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String dateLabel(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

String durationLabel(Duration value) =>
    '${value.inHours.toString().padLeft(2, '0')}:${(value.inMinutes % 60).toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
