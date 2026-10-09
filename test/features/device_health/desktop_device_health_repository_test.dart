import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/features/device_health/data/desktop_device_health_repository.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';
import 'package:knight_rise/features/device_health/domain/health_issue.dart';
import 'package:knight_rise/features/scheduler/desktop/desktop_heartbeat.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fakes.dart';
import '../../helpers/health_fakes.dart';

class _MockHeartbeat extends Mock implements DesktopHeartbeat;

class _FakeProbe implements DesktopRuntimeProbe {
  bool? napDisabled = true;
  bool throws = false;

  @override
  Future<bool?> appNapDisabled() async {
    if (throws) throw StateError('no channel');
    return napDisabled;
  }
}

class _ThrowingLaunch extends FakeLaunchAtLogin {
  @override
  Future<LaunchAtLoginStatus> status() async => throw StateError('registry');
}

void main() {
  late FakeNotificationGateway gateway;
  late _MockHeartbeat heartbeat;
  late _FakeProbe probe;
  late FixedClock clock;
  final now = DateTime(2026, 1, 1, 12);

  setUp(() {
    gateway = FakeNotificationGateway();
    heartbeat = _MockHeartbeat();
    probe = _FakeProbe();
    clock = FixedClock(now);
    when(() => heartbeat.lastBeatAt).thenReturn(now.subtract(const Duration(seconds: 40)));
    when(() => heartbeat.timerLag).thenReturn(null);
    when(() => heartbeat.beatNow()).thenAnswer((_) async {});
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  DesktopDeviceHealthRepository build([FakeLaunchAtLogin? launch]) =>
      DesktopDeviceHealthRepository(gateway, launch ?? FakeLaunchAtLogin(), heartbeat, probe, clock);

  test('macOS gathers every signal', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final report = await build().load();
    expect(report.platform, HealthPlatform.macos);
    expect(report.notificationsEnabled, isTrue);
    expect(report.notificationsVerifiable, isTrue);
    expect(report.launchAtLogin, LaunchAtLoginStatus.enabled);
    expect(report.lastHeartbeatAt, now.subtract(const Duration(seconds: 40)));
    expect(report.checkedAt, now);
    expect(report.appNapDisabled, isTrue);
    expect(report.exactAlarmsAllowed, isTrue);
    expect(issuesOf(report), isEmpty);
  });

  test('macOS reads the notification toggle', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    gateway.enabled = false;
    final report = await build().load();
    expect(report.notificationsEnabled, isFalse);
    expect(issuesOf(report).map((i) => i.kind), [HealthKind.notifications]);
  });

  test('Windows: notifications unverifiable, App Nap unknown', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    gateway.enabled = false;
    final report = await build().load();
    expect(report.platform, HealthPlatform.windows);
    expect(report.notificationsVerifiable, isFalse);
    expect(report.appNapDisabled, isNull);
    expect(issuesOf(report).map((i) => i.kind), [HealthKind.notificationsUnverified]);
  });

  test('a heartbeat still stale after an on-demand beat is an error', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    when(() => heartbeat.lastBeatAt).thenReturn(now.subtract(const Duration(minutes: 5)));
    expect(issuesOf(await build().load()).map((i) => i.kind), [HealthKind.heartbeat]);
    verify(() => heartbeat.beatNow()).called(1);
  });

  test('right after a wake the on-demand beat clears a stale heartbeat', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var beat = now.subtract(const Duration(minutes: 90)); // the machine slept
    when(() => heartbeat.lastBeatAt).thenAnswer((_) => beat);
    when(() => heartbeat.beatNow()).thenAnswer((_) async => beat = now);
    final report = await build().load();
    expect(report.lastHeartbeatAt, now);
    expect(issuesOf(report), isEmpty);
  });

  test('a fresh heartbeat is not beaten again; its timer lag is reported', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    when(() => heartbeat.timerLag).thenReturn(const Duration(seconds: 45));
    final report = await build().load();
    verifyNever(() => heartbeat.beatNow());
    expect(report.timerLag, const Duration(seconds: 45));
    expect(issuesOf(report).map((i) => i.kind), [HealthKind.heartbeat]);
  });

  test('before the first beat the heartbeat is unknown, not an error', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    when(() => heartbeat.lastBeatAt).thenReturn(null);
    final report = await build().load();
    expect(report.lastHeartbeatAt, isNull);
    expect(issuesOf(report), isEmpty);
  });

  test('never throws: failing signals come back null', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    probe.throws = true;
    final report = await build(_ThrowingLaunch()).load();
    expect(report.launchAtLogin, isNull);
    expect(report.appNapDisabled, isNull);
  });
}
