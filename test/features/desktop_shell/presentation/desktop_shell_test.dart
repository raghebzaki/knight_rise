import 'dart:async';
import 'dart:ui' show Locale, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/platform/device_locales.dart';
import 'package:knight_rise/features/desktop_shell/data/tray_port.dart';
import 'package:knight_rise/features/desktop_shell/data/window_port.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/features/desktop_shell/domain/tray_menu_model.dart';
import 'package:knight_rise/features/desktop_shell/presentation/app_exit.dart';
import 'package:knight_rise/features/desktop_shell/presentation/desktop_shell.dart';
import 'package:knight_rise/features/scheduler/desktop/desktop_alarm_clock.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/tz.dart';

class _MockAlarm extends Mock implements DesktopAlarmClock;

class _MockStart extends Mock implements StartShield;

class _MockEnd extends Mock implements EndShield;

class _Device implements DeviceLocales {
  @override
  List<Locale> get current => const [Locale('en')];
}

class _FakeWindow implements WindowPort {
  final calls = <String>[];
  final close = StreamController<void>.broadcast();
  bool throwOnInit = false;
  bool minimized = false;

  @override
  Stream<void> get closeRequests => close.stream;

  @override
  Future<void> ensureInitialized() async {
    calls.add('init');
    if (throwOnInit) throw StateError('no window');
  }

  @override
  Future<void> setPreventClose(bool v) async => calls.add('preventClose:$v');

  @override
  Future<void> show() async => calls.add('show');

  @override
  Future<void> focus() async => calls.add('focus');

  @override
  Future<void> hide() async => calls.add('hide');

  @override
  Future<bool> isVisible() async => true;

  @override
  Future<bool> isMinimized() async => minimized;

  @override
  Future<void> restore() async {
    calls.add('restore');
    minimized = false;
  }

  @override
  Future<void> setMinimumSize(Size size) async => calls.add('minSize:${size.width.toInt()}x${size.height.toInt()}');

  @override
  Future<void> destroy() async => calls.add('destroy');
}

class _FakeTray implements TrayPort {
  final calls = <String>[];
  final menus = <List<TrayMenuEntry>>[];
  String? icon;
  bool? template;
  String? tooltip;
  final cmd = StreamController<TrayCommand>.broadcast();
  final click = StreamController<TrayClick>.broadcast();

  @override
  Stream<TrayCommand> get commands => cmd.stream;

  @override
  Stream<TrayClick> get clicks => click.stream;

  @override
  Future<void> setIcon(String assetPath, {bool isTemplate = false}) async {
    icon = assetPath;
    template = isTemplate;
    calls.add('icon');
  }

  @override
  Future<void> setToolTip(String text) async {
    tooltip = text;
    calls.add('tooltip');
  }

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) async {
    menus.add(entries);
    calls.add('menu');
  }

  @override
  Future<void> popUp() async => calls.add('popUp');

  @override
  Future<void> destroy() async => calls.add('destroy');
}

class _FakeLaunch implements LaunchAtLogin {
  LaunchAtLoginStatus current = LaunchAtLoginStatus.disabled;
  final sets = <bool>[];

  @override
  Future<LaunchAtLoginStatus> status() async => current;

  @override
  Future<LaunchAtLoginStatus> setEnabled(bool enabled) async {
    sets.add(enabled);
    return current = enabled ? LaunchAtLoginStatus.enabled : LaunchAtLoginStatus.disabled;
  }

  @override
  Future<bool> launchedAtLogin() async => false;
}

class _FakeExit implements AppExit {
  _FakeExit(this.log);

  /// Shared with the fake window, so the quit order is observable.
  final List<String> log;
  int exits = 0;

  @override
  Future<void> exit() async {
    exits++;
    log.add('exit');
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 9, 9);
  late _FakeWindow window;
  late _FakeTray tray;
  late _FakeLaunch launch;
  late _FakeExit exit;
  late _MockAlarm alarm;
  late _MockStart start;
  late _MockEnd end;
  late FakeShieldRepository shields;
  late DesktopShell shell;

  setUpAll(() => registerFallbackValue(ShieldPreset.min25));

  setUp(() {
    window = _FakeWindow();
    tray = _FakeTray();
    launch = _FakeLaunch();
    exit = _FakeExit(window.calls);
    alarm = _MockAlarm();
    start = _MockStart();
    end = _MockEnd();
    shields = FakeShieldRepository();
    when(() => alarm.nextFireAt).thenReturn(null);
    when(() => start(any())).thenAnswer((_) async => null);
    when(() => end()).thenAnswer((_) async => null);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    shell = DesktopShell(
      window,
      tray,
      launch,
      alarm,
      shields,
      start,
      end,
      FakeSettingsRepository(),
      _Device(),
      FakeLocationProvider(cairo),
      FixedClock(now),
      exit,
    );
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  group('start', () {
    test('prevents close, sets the Windows icon, tooltip and menu', () async {
      await shell.start();
      expect(window.calls, ['init', 'preventClose:true', 'minSize:400x640']);
      expect(tray.icon, 'assets/branding/tray/tray_icon.ico');
      expect(tray.template, isFalse);
      expect(tray.tooltip, 'Knight Rise');
      expect(tray.menus, hasLength(1));
    });

    test('uses the template icon on macOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await shell.start();
      expect(tray.icon, 'assets/branding/tray/tray_icon_template.png');
      expect(tray.template, isTrue);
    });

    test('is idempotent', () async {
      await shell.start();
      await shell.start();
      expect(window.calls.where((c) => c == 'init'), hasLength(1));
      expect(tray.menus, hasLength(1));
      window.close.add(null);
      await pump();
      expect(window.calls.where((c) => c == 'hide'), hasLength(1));
    });

    test('survives a throwing window and still builds the tray', () async {
      window.throwOnInit = true;
      await shell.start();
      expect(tray.menus, hasLength(1));
    });
  });

  test('a close request hides the window (close-to-tray), never destroys it', () async {
    await shell.start();
    window.calls.clear();
    window.close.add(null);
    await pump();
    expect(window.calls, ['hide']);
  });

  test('Windows left click brings the window to front', () async {
    await shell.start();
    window.calls.clear();
    tray.click.add(TrayClick.left);
    await pump();
    expect(window.calls, ['show', 'focus']);
    expect(tray.calls.where((c) => c == 'popUp'), isEmpty);
  });

  test('right click rebuilds the menu with current data, then pops up', () async {
    await shell.start();
    final next = DateTime.utc(2026, 10, 9, 14, 30);
    when(() => alarm.nextFireAt).thenReturn(next);
    launch.current = LaunchAtLoginStatus.enabled;
    tray.calls.clear();
    tray.click.add(TrayClick.right);
    await pump();
    expect(tray.calls, ['menu', 'popUp']);
    final menu = tray.menus.last;
    expect(menu.first.label, contains('Next reminder at'));
    expect(menu.firstWhere((e) => e.command == TrayCommand.toggleLaunchAtLogin).checked, isTrue);
  });

  test('an active shield shows in the rebuilt menu', () async {
    await shields.add(
      ShieldSession(
        startAt: now.subtract(const Duration(minutes: 1)),
        endAt: now.add(const Duration(minutes: 20)),
        reason: ShieldReason.focus,
      ),
    );
    await shell.start();
    expect(tray.menus.last.first.label, startsWith('Shield up until'));
  });

  test('macOS: any click pops up the menu', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await shell.start();
    tray.calls.clear();
    tray.click.add(TrayClick.left);
    await pump();
    expect(tray.calls, ['menu', 'popUp']);
  });

  group('commands', () {
    setUp(() async {
      await shell.start();
      window.calls.clear();
    });

    test('open', () async {
      tray.cmd.add(TrayCommand.open);
      await pump();
      expect(window.calls, ['show', 'focus']);
    });

    test('shield presets', () async {
      tray.cmd
        ..add(TrayCommand.shield25)
        ..add(TrayCommand.shield50);
      await pump();
      verify(() => start(ShieldPreset.min25)).called(1);
      verify(() => start(ShieldPreset.min50)).called(1);
    });

    test('end shield', () async {
      tray.cmd.add(TrayCommand.endShield);
      await pump();
      verify(() => end()).called(1);
    });

    test('toggle launch at login flips and refreshes the menu', () async {
      final before = tray.menus.length;
      tray.cmd.add(TrayCommand.toggleLaunchAtLogin);
      await pump();
      expect(launch.sets, [true]);
      expect(tray.menus, hasLength(before + 1));
      tray.cmd.add(TrayCommand.toggleLaunchAtLogin);
      await pump();
      expect(launch.sets, [true, false]);
    });

    test('quit destroys the tray, allows close, then exits', () async {
      tray.calls.clear();
      tray.cmd.add(TrayCommand.quit);
      await pump();
      expect(tray.calls, ['destroy']);
      expect(window.calls, ['preventClose:false', 'exit'], reason: 'close must be allowed before exiting');
      expect(exit.exits, 1);
    });
  });

  group('bringToFront', () {
    test('shows then focuses a window that is not minimized, without restoring', () async {
      await shell.bringToFront();
      expect(window.calls, ['show', 'focus']);
    });

    test('restores a minimized window at its bounds before showing and focusing', () async {
      window.minimized = true;
      await shell.bringToFront();
      expect(window.calls, ['restore', 'show', 'focus']);
    });

    test('never moves or resizes the window', () async {
      window.minimized = true;
      await shell.start();
      window.close.add(null);
      await pump();
      await shell.bringToFront();
      expect(window.calls.where((c) => c.startsWith('minSize')), hasLength(1), reason: 'only the start-up minimum');
      expect(window.calls, isNot(contains('destroy')));
    });
  });
}
