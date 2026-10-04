import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/time/timezone_loader.dart';

/// The device's current IANA zone id. Abstracted so tests can fake the
/// platform call.
abstract interface class DeviceTimezone {
  /// Null when the platform lookup fails.
  Future<String?> currentId();
}

@LazySingleton(as: DeviceTimezone)
class PlatformDeviceTimezone implements DeviceTimezone {
  const PlatformDeviceTimezone();

  @override
  Future<String?> currentId() => deviceTimezoneId();
}
