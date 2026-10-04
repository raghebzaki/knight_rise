import 'package:timezone/timezone.dart' as tz;

/// Local midnight at the start of the day containing [instant].
tz.TZDateTime startOfLocalDay(DateTime instant, tz.Location location) {
  final local = tz.TZDateTime.from(instant, location);
  return tz.TZDateTime(location, local.year, local.month, local.day);
}
