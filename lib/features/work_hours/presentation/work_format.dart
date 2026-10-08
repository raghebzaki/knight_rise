import 'package:intl/intl.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/domain/work_week.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// "09:00"; minute 1440 reads "24:00".
String formatMinuteOfDay(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

/// "09:00 – 17:00".
String formatWindow(TimeWindow w) => '${formatMinuteOfDay(w.startMinute)} – ${formatMinuteOfDay(w.endMinute)}';

String weekdayName(String locale, int weekday, {bool short = false}) {
  final symbols = DateFormat('E', locale).dateSymbols;
  return (short ? symbols.SHORTWEEKDAYS : symbols.WEEKDAYS)[weekday % 7];
}

/// "Sun–Thu · 09:00–17:00", "Sun, Tue · 09:00–12:00, 13:00–17:00", or the
/// localized "Custom" / "No work days".
String workScheduleSummary(AppLocalizations l, String locale, WorkSchedule schedule) {
  final uniform = uniformSchedule(schedule);
  if (uniform == null) return l.settingsWorkHoursCustom;
  if (uniform.days.isEmpty) return l.settingsWorkHoursNone;
  final days = uniform.days;
  final order = [for (final d in days) weekdaysSundayFirst.indexOf(d)];
  final contiguous = [for (var i = 1; i < order.length; i++) order[i] - order[i - 1] == 1].every((e) => e);
  String name(int d) => weekdayName(locale, d, short: true);
  final dayLabel = days.length >= 3 && contiguous
      ? '${name(days.first)}–${name(days.last)}'
      : days.map(name).join(', ');
  final times = uniform.windows
      .map((w) => '${formatMinuteOfDay(w.startMinute)}–${formatMinuteOfDay(w.endMinute)}')
      .join(', ');
  return '$dayLabel · $times';
}
