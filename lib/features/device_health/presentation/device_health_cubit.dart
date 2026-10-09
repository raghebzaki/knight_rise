import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/core/platform/desktop_settings_links.dart';
import 'package:knight_rise/core/platform/system_settings_launcher.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/features/device_health/data/device_health_platform.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';
import 'package:knight_rise/features/device_health/domain/device_health_repository.dart';
import 'package:knight_rise/features/device_health/domain/health_issue.dart';
import 'package:knight_rise/features/device_health/domain/oem_guide.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';

class DeviceHealthState extends Equatable {
  const DeviceHealthState({this.report, this.issues = const [], this.awaitingExactAlarms = false});

  /// Null until the first refresh completes.
  final DeviceHealthReport? report;
  final List<HealthIssue> issues;

  /// The user asked for Precision Timing and was sent to the system screen;
  /// the setting is saved on the next refresh once the OS allows it.
  final bool awaitingExactAlarms;

  bool get loaded => report != null;

  HealthIssue? issue(HealthKind kind) => issues.where((i) => i.kind == kind).firstOrNull;

  /// Warnings and errors (info-level hints excluded).
  List<HealthIssue> get actionable => actionableIssues(issues);

  @override
  List<Object?> get props => [report, issues, awaitingExactAlarms];
}

@injectable
class DeviceHealthCubit extends Cubit<DeviceHealthState> {
  DeviceHealthCubit(
    this._repository,
    this._gateway,
    this._settings,
    this._launcher,
    this._platform,
    this._links,
    this._launchAtLogin,
  ) : super(const DeviceHealthState());

  final DeviceHealthRepository _repository;
  final NotificationGateway _gateway;
  final SettingsRepository _settings;
  final SystemSettingsLauncher _launcher;
  final DeviceHealthPlatform _platform;
  final DesktopSettingsLinks _links;
  final LaunchAtLogin _launchAtLogin;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  bool get _desktop => isDesktopPlatform(defaultTargetPlatform);

  /// Re-reads every signal. Call on open and on every app resume.
  Future<void> refresh() async {
    var report = await _repository.load();
    if (isClosed) return;
    var awaiting = state.awaitingExactAlarms;
    if (awaiting && report.exactAlarmsAllowed) {
      // The user came back from the system screen having allowed exact alarms.
      awaiting = false;
      if (!report.precisionTiming) {
        await _savePrecision(value: true);
        report = await _repository.load();
        if (isClosed) return;
      }
    }
    emit(DeviceHealthState(report: report, issues: issuesOf(report), awaitingExactAlarms: awaiting));
  }

  /// Runs the fix for [kind].
  Future<void> fix(HealthKind kind) async {
    switch (kind) {
      case HealthKind.notifications:
        if (!await _gateway.requestPermission()) {
          if (_desktop) {
            await _links.openNotifications();
          } else if (_android) {
            if (!await _launcher.openAppNotificationSettings()) await _launcher.openAppDetailsSettings();
          } else {
            await _platform.openAppSettings();
          }
        }
      case HealthKind.exactAlarms:
        await _gateway.requestExactAlarmPermission();
      case HealthKind.battery when _desktop:
        await _links.openBatterySettings();
      case HealthKind.battery:
        if (!await _launcher.openBatteryOptimizationSettings()) await _launcher.openAppDetailsSettings();
      case HealthKind.backgroundRefresh:
        await _platform.openAppSettings();
      case HealthKind.launchAtLogin:
        final status = await _launchAtLogin.status();
        if (status == LaunchAtLoginStatus.requiresApproval) {
          await _links.openLoginItems();
        } else {
          await _launchAtLogin.setEnabled(true);
        }
      case HealthKind.notificationsUnverified:
        await _links.openNotifications();
      case HealthKind.heartbeat || HealthKind.appNap:
        break; // Informational: nothing the user can fix from here.
    }
    await refresh();
  }

  /// The Launch at login switch (desktop).
  Future<void> setLaunchAtLogin({required bool value}) async {
    await _launchAtLogin.setEnabled(value);
    await refresh();
  }

  /// Opens the OS notification settings (desktop), then re-reads.
  Future<void> openNotificationSettings() async {
    await _links.openNotifications();
    await refresh();
  }

  /// Opens the OS login-items screen (desktop), then re-reads.
  Future<void> openLoginItems() async {
    await _links.openLoginItems();
    await refresh();
  }

  /// Opens the OS battery settings (desktop).
  Future<void> openBatterySettings() async {
    await _links.openBatterySettings();
    await refresh();
  }

  /// The Precision Timing switch. Turning it on without the OS permission
  /// sends the user to the system screen and saves once it is granted.
  Future<void> setPrecisionTiming({required bool value}) async {
    if (!value) {
      emit(DeviceHealthState(report: state.report, issues: state.issues));
      await _savePrecision(value: false);
    } else if (await _gateway.canScheduleExact()) {
      await _savePrecision(value: true);
    } else {
      emit(DeviceHealthState(report: state.report, issues: state.issues, awaitingExactAlarms: true));
      await _gateway.requestExactAlarmPermission();
    }
    await refresh();
  }

  /// OEM "Open settings": tries the maker's known screens, then app details.
  Future<void> openOemSettings(OemGuide guide) async {
    for (final component in guide.settingsComponents) {
      if (await _launcher.openComponent(component)) return;
    }
    if (_android) await _launcher.openAppDetailsSettings();
  }

  Future<void> _savePrecision({required bool value}) async {
    final current = await _settings.get();
    await _settings.save(current.copyWith(precisionTiming: value));
  }
}
