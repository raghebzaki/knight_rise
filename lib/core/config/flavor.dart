/// Build flavor, set with `--dart-define=FLAVOR=prod`. Defaults to dev.
///
/// Native Android/iOS flavors (separate app ids and icons) are added when
/// store builds begin; until then this Dart-side switch gates dev tooling
/// such as the widget gallery and the BLoC logger.
enum Flavor {
  dev,
  prod;

  static final Flavor current =
      Flavor.values.asNameMap()[const String.fromEnvironment('FLAVOR', defaultValue: 'dev')] ?? Flavor.dev;

  bool get isDev => this == Flavor.dev;
}
