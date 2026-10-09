import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';
import 'package:knight_rise/features/device_health/domain/device_health_repository.dart';
import 'package:knight_rise/features/device_health/domain/health_issue.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/scheduler/desktop/desktop_heartbeat.dart';

/// Desktop runtime facts only the native runner knows.
abstract interface class DesktopRuntimeProbe {
  /// macOS: whether the runner currently holds the activity that opts the app
  /// out of App Nap. Null when unknown (not macOS, or the channel is missing).
  Future<bool?> appNapDisabled();
}

/// Asks the macOS runner over the `knight_rise/desktop` channel.
@desktopEnv
@LazySingleton(as: DesktopRuntimeProbe)
class ChannelDesktopRuntimeProbe implements DesktopRuntimeProbe {
  ChannelDesktopRuntimeProbe();

  static const MethodChannel _channel = MethodChannel('knight_rise/desktop');

  @override
  Future<bool?> appNapDisabled() async {
    if (defaultTargetPlatform != TargetPlatform.macOS) return null;
    try {
      return await _channel.invokeMethod<bool>('appNapDisabled');
    } on Object {
      return null;
    }
  }
}

/// Gathers the macOS / Windows health signals. Never throws; a signal that
/// cannot be read comes back null.
@desktopEnv
@LazySingleton(as: DeviceHealthRepository)
class DesktopDeviceHealthRepository implements DeviceHealthRepository {
  DesktopDeviceHealthRepository(this._gateway, this._launchAtLogin, this._heartbeat, this._probe, this._clock);

  final NotificationGateway _gateway;
  final LaunchAtLogin _launchAtLogin;
  final DesktopHeartbeat _heartbeat;
  final DesktopRuntimeProbe _probe;
  final Clock _clock;

  @override
  Future<DeviceHealthReport> load() async {
    final windows = defaultTargetPlatform == TargetPlatform.windows;
    // Right after a wake the next timer beat can be up to a minute away; beat
    // now so a sleeping machine is not reported as a stalled heartbeat. A
    // heartbeat that is really stuck stays stale even after this.
    final beat = _heartbeat.lastBeatAt;
    if (beat != null && _clock.now().difference(beat) > heartbeatStaleAfter) {
      await _safe<void>(_heartbeat.beatNow);
    }
    return DeviceHealthReport(
      platform: windows ? HealthPlatform.windows : HealthPlatform.macos,
      // The Windows plugin cannot read the toggle: assume on, flag unverifiable.
      notificationsEnabled: windows || await _safe(_gateway.notificationsEnabled) == true,
      notificationsVerifiable: !windows,
      // Precision Timing is a mobile concept; the in-process timer is always exact.
      precisionTiming: false,
      exactAlarmsAllowed: true,
      launchAtLogin: await _safe(_launchAtLogin.status),
      lastHeartbeatAt: _heartbeat.lastBeatAt,
      timerLag: _heartbeat.timerLag,
      checkedAt: _clock.now(),
      appNapDisabled: windows ? null : await _safe(_probe.appNapDisabled),
    );
  }

  static Future<T?> _safe<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on Object catch (e) {
      debugPrint('[device-health] signal unavailable: $e');
      return null;
    }
  }
}
