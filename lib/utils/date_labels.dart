import 'package:intl/intl.dart';

/// Date and time formatting for the chat ("Today", "Yesterday", "17:42").
abstract final class DateLabels {
  static final DateFormat _weekday = DateFormat.EEEE();
  static final DateFormat _monthDay = DateFormat.MMMMd();
  static final DateFormat _fullDate = DateFormat.yMMMMd();
  static final DateFormat _time24 = DateFormat.Hm();
  static final DateFormat _time12 = DateFormat.jm();

  /// Whether [a] and [b] fall on the same calendar day (local time).
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Label of the date separator shown above the first message of a day.
  static String day(DateTime date, {DateTime? now}) {
    final today = now ?? DateTime.now();
    if (isSameDay(date, today)) return 'Today';
    // Calendar arithmetic (not "minus 24 hours") so DST changes are harmless.
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    if (isSameDay(date, yesterday)) return 'Yesterday';
    final weekAgo = DateTime(today.year, today.month, today.day - 6);
    if (date.isAfter(weekAgo) && date.isBefore(today)) {
      return _weekday.format(date);
    }
    return date.year == today.year
        ? _monthDay.format(date)
        : _fullDate.format(date);
  }

  /// Short time shown inside a bubble.
  static String time(DateTime date, {bool use24HourFormat = true}) =>
      (use24HourFormat ? _time24 : _time12).format(date);
}
