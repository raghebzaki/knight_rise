import 'package:flutter/foundation.dart';

/// Explicit `--dart-define=FLAVOR=dev|prod`, if any.
const String _defined = String.fromEnvironment('FLAVOR');

/// Set by `flutter build/run --flavor <name>` (Android product flavors).
const String _native = String.fromEnvironment('FLUTTER_APP_FLAVOR');

/// The build flavor's name: an explicit `FLAVOR` define wins, then the native
/// `--flavor`; with neither, release builds are prod and debug/profile builds
/// are dev, so a forgotten flag can never ship dev tools.
@visibleForTesting
String resolveFlavorName({required String defined, required String native, required bool release}) {
  for (final name in [defined, native]) {
    if (name == 'dev' || name == 'prod') return name;
  }
  return release ? 'prod' : 'dev';
}

/// True for the dev flavor. A compile-time constant, so code behind
/// `if (kDevFlavor)` (widget gallery, diagnostics, BLoC logger) is
/// tree-shaken out of prod release builds.
const bool kDevFlavor =
    _defined == 'dev' || (_defined != 'prod' && (_native == 'dev' || (_native != 'prod' && !kReleaseMode)));

/// Build flavor. Native flavors (Android `productFlavors`) give dev its own
/// application id (`.dev`), name and icon so both can be installed side by side.
enum Flavor {
  dev,
  prod;

  static const Flavor current = kDevFlavor ? Flavor.dev : Flavor.prod;

  bool get isDev => this == Flavor.dev;
}
