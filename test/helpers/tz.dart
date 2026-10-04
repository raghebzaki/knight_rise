import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

var _loaded = false;

tz.Location loc(String name) {
  if (!_loaded) {
    tzdata.initializeTimeZones();
    _loaded = true;
  }
  return tz.getLocation(name);
}

tz.Location get cairo => loc('Africa/Cairo');
tz.Location get newYork => loc('America/New_York');

/// Wall-clock time in [l].
tz.TZDateTime at(tz.Location l, int y, int m, int d, [int h = 0, int min = 0]) => tz.TZDateTime(l, y, m, d, h, min);
