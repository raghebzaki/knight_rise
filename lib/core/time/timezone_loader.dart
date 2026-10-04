import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// IANA id of the device's current zone, or null if the platform lookup fails.
Future<String?> deviceTimezoneId() async {
  try {
    return (await FlutterTimezone.getLocalTimezone()).identifier;
  } on Object catch (e) {
    debugPrint('Timezone lookup failed: $e');
    return null;
  }
}

/// Loads the IANA database and resolves the device's local zone.
/// Falls back to UTC if the platform reports an unknown identifier.
Future<tz.Location> loadLocalLocation() async {
  tzdata.initializeTimeZones();
  try {
    final id = await deviceTimezoneId();
    if (id == null) return tz.UTC;
    final location = tz.getLocation(id);
    tz.setLocalLocation(location);
    return location;
  } on Object catch (e) {
    debugPrint('Timezone lookup failed, using UTC: $e');
    return tz.UTC;
  }
}
