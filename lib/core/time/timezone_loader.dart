import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Loads the IANA database and resolves the device's local zone.
/// Falls back to UTC if the platform reports an unknown identifier.
Future<tz.Location> loadLocalLocation() async {
  tzdata.initializeTimeZones();
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    final location = tz.getLocation(info.identifier);
    tz.setLocalLocation(location);
    return location;
  } on Object catch (e) {
    debugPrint('Timezone lookup failed, using UTC: $e');
    return tz.UTC;
  }
}
