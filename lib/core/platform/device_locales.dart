import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale;
import 'package:injectable/injectable.dart';

/// The device's preferred languages, most preferred first.
abstract interface class DeviceLocales {
  List<Locale> get current;
}

@LazySingleton(as: DeviceLocales)
class PlatformDeviceLocales implements DeviceLocales {
  const PlatformDeviceLocales();

  @override
  List<Locale> get current => PlatformDispatcher.instance.locales;
}
