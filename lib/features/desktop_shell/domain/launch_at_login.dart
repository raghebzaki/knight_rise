/// Whether the app starts when the user signs in.
enum LaunchAtLoginStatus {
  /// Registered and effective.
  enabled,

  /// Not registered.
  disabled,

  /// Registered, but the user must approve it in system settings (macOS).
  requiresApproval,

  /// This build or platform cannot register (unsupported, or not found).
  unavailable,
}

/// Launch-at-login registration. Implementations never throw: failures are
/// logged and reported as [LaunchAtLoginStatus.unavailable] / `false`.
abstract interface class LaunchAtLogin {
  /// The current registration state.
  Future<LaunchAtLoginStatus> status();

  /// Registers or unregisters, returning the resulting state.
  // ignore: avoid_positional_boolean_parameters
  Future<LaunchAtLoginStatus> setEnabled(bool enabled);

  /// True when this process was started by the login item rather than opened
  /// by the user.
  Future<bool> launchedAtLogin();
}

/// For platforms without a registration mechanism.
class UnsupportedLaunchAtLogin implements LaunchAtLogin {
  const UnsupportedLaunchAtLogin();

  @override
  Future<LaunchAtLoginStatus> status() async => LaunchAtLoginStatus.unavailable;

  @override
  Future<LaunchAtLoginStatus> setEnabled(bool enabled) async => LaunchAtLoginStatus.unavailable;

  @override
  Future<bool> launchedAtLogin() async => false;
}
