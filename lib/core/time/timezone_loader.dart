import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// IANA id of the device's current zone, or null if the platform lookup fails.
///
/// Windows maps its own zone names to IANA ids through ICU (CLDR
/// `windowsZones`), which may return legacy alias spellings such as
/// `Asia/Calcutta`; the bundled database resolves those. A zone ICU cannot map
/// comes back as `Etc/Unknown`, which [resolveLocation] handles.
Future<String?> deviceTimezoneId() async {
  try {
    return (await FlutterTimezone.getLocalTimezone()).identifier;
  } on Object catch (e) {
    debugPrint('Timezone lookup failed: $e');
    return null;
  }
}

/// The location for the platform-reported [id]. When [id] is missing or not
/// in the IANA database, falls back to the fixed-offset `Etc/GMT±N` zone for
/// [utcOffset] (whole hours only; no DST), so wall-clock reminders still land
/// at the right local time, and to UTC otherwise. Requires the database to be
/// initialized.
tz.Location resolveLocation(String? id, {required Duration utcOffset}) {
  if (id != null) {
    final location = tz.timeZoneDatabase.locations[id];
    if (location != null) return location;
    debugPrint('Unknown timezone "$id", falling back to UTC offset $utcOffset');
  }
  final minutes = utcOffset.inMinutes;
  if (minutes % 60 != 0) return tz.UTC;
  final hours = minutes ~/ 60;
  if (hours == 0) return tz.UTC;
  // POSIX sign convention: Etc/GMT-3 is three hours *ahead* of UTC.
  return tz.timeZoneDatabase.locations['Etc/GMT${hours > 0 ? '-' : '+'}${hours.abs()}'] ?? tz.UTC;
}

/// Loads the IANA database and resolves the device's local zone (see
/// [resolveLocation] for the fallback when the platform reports no usable id).
Future<tz.Location> loadLocalLocation() async {
  tzdata.initializeTimeZones();
  final location = resolveLocation(await deviceTimezoneId(), utcOffset: DateTime.now().timeZoneOffset);
  tz.setLocalLocation(location);
  return location;
}
