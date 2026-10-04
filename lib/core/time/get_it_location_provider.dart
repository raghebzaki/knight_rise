import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:timezone/timezone.dart' as tz;

/// Reads the `tz.Location` registered in [getIt] on every access.
/// `ScheduleSyncService` re-registers it when the device zone changes.
@LazySingleton(as: LocationProvider)
class GetItLocationProvider implements LocationProvider {
  const GetItLocationProvider();

  @override
  tz.Location get current => getIt<tz.Location>();
}
