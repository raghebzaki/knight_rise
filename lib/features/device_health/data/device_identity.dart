import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

/// Who made this device.
abstract interface class DeviceIdentity {
  /// Manufacturer and brand joined by a space (`Xiaomi Redmi`); empty when
  /// unknown or not Android.
  Future<String> manufacturer();
}

@LazySingleton(as: DeviceIdentity)
class DeviceInfoIdentity implements DeviceIdentity {
  DeviceInfoIdentity();

  @override
  Future<String> manufacturer() async {
    if (defaultTargetPlatform != TargetPlatform.android) return '';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return '${info.manufacturer} ${info.brand}'.trim();
    } on Object {
      return '';
    }
  }
}
