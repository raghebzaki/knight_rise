import 'package:timezone/timezone.dart' as tz;

/// Local midnight at the start of the day containing [instant].
tz.TZDateTime startOfLocalDay(DateTime instant, tz.Location location) {
  final local = tz.TZDateTime.from(instant, location);
  return tz.TZDateTime(location, local.year, local.month, local.day);
}

/// The local calendar date of [instant] in [location], as a date-only value
/// (`DateTime.utc(y, m, d)`). Date-only values never carry a zone, so they
/// stay stable across DST and device zone changes.
DateTime localDateOf(DateTime instant, tz.Location location) {
  final local = tz.TZDateTime.from(instant, location);
  return DateTime.utc(local.year, local.month, local.day);
}

/// Normalizes any [DateTime] to a date-only value using its own calendar
/// fields (no zone conversion).
DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// `YYYY-MM-DD` key of [d]'s own calendar fields. Used as the primary key of
/// per-date records such as day overrides.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Inverse of [dateKey]; returns a date-only value. Throws [FormatException]
/// on malformed input.
DateTime parseDateKey(String key) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (m == null) throw FormatException('Not a YYYY-MM-DD date key', key);
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}
