import 'package:timezone/timezone.dart' as tz;

/// The user's current [tz.Location], resolved at access time (not injection
/// time) so long-lived objects pick up a timezone change.
abstract interface class LocationProvider {
  tz.Location get current;
}
