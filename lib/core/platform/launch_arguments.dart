/// Command-line arguments the process was started with, captured by `main`.
abstract final class LaunchArguments {
  /// Set once, as the first statement of `main`.
  static List<String> values = const [];

  /// True when the OS started the app at login (`--autostart`), as opposed to
  /// the user opening it.
  static bool get autostart => values.contains('--autostart');
}
