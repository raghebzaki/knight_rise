import 'dart:async';

import 'package:knight_rise/core/platform/desktop_settings_links.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/features/device_health/data/device_health_platform.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';
import 'package:knight_rise/features/device_health/domain/device_health_repository.dart';
import 'package:knight_rise/features/device_health/presentation/device_health_cubit.dart';
import 'package:knight_rise/features/scheduler/presentation/schedule_sync_service.dart';

import 'fake_launcher.dart';
import 'fakes.dart';

/// Returns [report]; tests mutate it between refreshes.
class FakeDeviceHealthRepository implements DeviceHealthRepository {
  FakeDeviceHealthRepository([
    this.report = const DeviceHealthReport(
      notificationsEnabled: true,
      precisionTiming: false,
      exactAlarmsAllowed: true,
      platform: HealthPlatform.android,
      batteryOptimizationIgnored: true,
      manufacturer: 'Google Pixel',
    ),
  ]);

  DeviceHealthReport report;

  /// When set, the report is rebuilt from the fakes on every [load]
  /// (so that saved settings and permission changes show up).
  DeviceHealthReport Function()? builder;

  @override
  Future<DeviceHealthReport> load() async => builder?.call() ?? report;
}

class FakeDeviceHealthPlatform implements DeviceHealthPlatform {
  bool? ignoringBattery = true;
  BackgroundRefresh? refresh = BackgroundRefresh.available;
  int openAppSettingsCalls = 0;

  @override
  Future<bool?> isIgnoringBatteryOptimizations() async => ignoringBattery;

  @override
  Future<BackgroundRefresh?> backgroundRefreshStatus() async => refresh;

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalls++;
    return true;
  }
}

/// Records the desktop settings screens that were opened.
class FakeDesktopSettingsLinks implements DesktopSettingsLinks {
  final List<String> calls = [];

  @override
  Future<bool> openNotifications() async {
    calls.add('notifications');
    return true;
  }

  @override
  Future<bool> openLoginItems() async {
    calls.add('loginItems');
    return true;
  }

  @override
  Future<bool> openBatterySettings() async {
    calls.add('battery');
    return true;
  }
}

/// In-memory [LaunchAtLogin].
class FakeLaunchAtLogin implements LaunchAtLogin {
  FakeLaunchAtLogin([this.current = LaunchAtLoginStatus.enabled]);

  LaunchAtLoginStatus current;
  final List<bool> sets = [];

  /// When set, [setEnabled] throws it.
  Object? throwOnSet;

  @override
  Future<LaunchAtLoginStatus> status() async => current;

  @override
  Future<LaunchAtLoginStatus> setEnabled(bool enabled) async {
    sets.add(enabled);
    final err = throwOnSet;
    if (err != null) {
      // Tests throw arbitrary objects on purpose.
      // ignore: only_throw_errors
      throw err;
    }
    return current = enabled ? LaunchAtLoginStatus.enabled : LaunchAtLoginStatus.disabled;
  }

  @override
  Future<bool> launchedAtLogin() async => false;
}

/// Fakes and a cubit wired to them. The repository rebuilds its report from
/// the gateway and settings, like the real one.
class HealthHarness {
  HealthHarness({HealthPlatform platform = HealthPlatform.android, String manufacturer = 'Google Pixel'}) {
    repository.builder = () => _report(platform, manufacturer);
    cubit = DeviceHealthCubit(repository, gateway, settings, launcher, platformFake, links, launchAtLogin);
  }

  /// Desktop signals the report is built from.
  DateTime now = DateTime(2026, 1, 1, 12);
  DateTime? lastBeat = DateTime(2026, 1, 1, 12);
  bool? appNapDisabled = true;

  final FakeDeviceHealthRepository repository = FakeDeviceHealthRepository();
  final FakeNotificationGateway gateway = FakeNotificationGateway();
  final FakeSettingsRepository settings = FakeSettingsRepository();
  final FakeSystemSettingsLauncher launcher = FakeSystemSettingsLauncher();
  final FakeDeviceHealthPlatform platformFake = FakeDeviceHealthPlatform();
  final FakeDesktopSettingsLinks links = FakeDesktopSettingsLinks();
  final FakeLaunchAtLogin launchAtLogin = FakeLaunchAtLogin();
  late final DeviceHealthCubit cubit;

  DeviceHealthReport _report(HealthPlatform platform, String manufacturer) {
    if (platform == HealthPlatform.macos || platform == HealthPlatform.windows) {
      final windows = platform == HealthPlatform.windows;
      return DeviceHealthReport(
        platform: platform,
        notificationsEnabled: windows || gateway.enabled,
        notificationsVerifiable: !windows,
        precisionTiming: false,
        exactAlarmsAllowed: true,
        launchAtLogin: launchAtLogin.current,
        lastHeartbeatAt: lastBeat,
        checkedAt: now,
        appNapDisabled: windows ? null : appNapDisabled,
      );
    }
    return _mobileReport(platform, manufacturer);
  }

  DeviceHealthReport _mobileReport(HealthPlatform platform, String manufacturer) => DeviceHealthReport(
    platform: platform,
    manufacturer: manufacturer,
    notificationsEnabled: gateway.enabled,
    precisionTiming: settings.current.precisionTiming,
    exactAlarmsAllowed: gateway.exactAllowed,
    batteryOptimizationIgnored: platform == HealthPlatform.android ? platformFake.ignoringBattery : null,
    backgroundRefresh: platform == HealthPlatform.ios ? platformFake.refresh : null,
  );
}

class FakeRemindersPausedSource implements RemindersPausedSource {
  final _controller = StreamController<void>.broadcast();

  @override
  DateTime? remindersPausedAt;

  @override
  Stream<void> get remindersWerePaused => _controller.stream;

  void emit() {
    remindersPausedAt = DateTime.now();
    _controller.add(null);
  }
}
