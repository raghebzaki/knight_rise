import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/platform/launch_arguments.dart';
import 'package:knight_rise/features/desktop_shell/data/macos_launch_at_login.dart';
import 'package:knight_rise/features/desktop_shell/data/package_identity.dart';
import 'package:knight_rise/features/desktop_shell/data/windows_launch_at_login.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';

class _MemoryStore implements RunKeyStore {
  final values = <String, String>{};
  bool failing = false;

  @override
  String? read(String name) {
    if (failing) throw StateError('registry');
    return values[name];
  }

  @override
  void write(String name, String value) {
    if (failing) throw StateError('registry');
    values[name] = value;
  }

  @override
  void delete(String name) {
    if (failing) throw StateError('registry');
    values.remove(name);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MacosLaunchAtLogin', () {
    const channel = MethodChannel('knight_rise/desktop');
    final calls = <MethodCall>[];
    Object? Function(MethodCall) handler = (_) => null;

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async {
        calls.add(c);
        return handler(c);
      });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('maps native statuses', () async {
      final impl = MacosLaunchAtLogin();
      final expected = {
        'enabled': LaunchAtLoginStatus.enabled,
        'notRegistered': LaunchAtLoginStatus.disabled,
        'requiresApproval': LaunchAtLoginStatus.requiresApproval,
        'notFound': LaunchAtLoginStatus.unavailable,
        'bogus': LaunchAtLoginStatus.unavailable,
      };
      for (final e in expected.entries) {
        handler = (_) => e.key;
        expect(await impl.status(), e.value, reason: e.key);
      }
      expect(calls.first.method, 'launchAtLoginStatus');
    });

    test('setEnabled sends the flag', () async {
      handler = (_) => 'enabled';
      expect(await MacosLaunchAtLogin().setEnabled(true), LaunchAtLoginStatus.enabled);
      expect(calls.single.method, 'setLaunchAtLogin');
      expect(calls.single.arguments, {'enabled': true});
    });

    test('platform errors become unavailable / false', () async {
      handler = (_) => throw PlatformException(code: 'launch_at_login_failed');
      final impl = MacosLaunchAtLogin();
      expect(await impl.setEnabled(true), LaunchAtLoginStatus.unavailable);
      expect(await impl.launchedAtLogin(), isFalse);
    });

    test('launchedAtLogin and settings pass through', () async {
      handler = (_) => true;
      final impl = MacosLaunchAtLogin();
      expect(await impl.launchedAtLogin(), isTrue);
      await impl.openSettings();
      expect(calls.last.method, 'openLoginItemsSettings');
    });

    test('a missing channel is unavailable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      expect(await MacosLaunchAtLogin().status(), LaunchAtLoginStatus.unavailable);
    });
  });

  group('WindowsLaunchAtLogin', () {
    late _MemoryStore store;
    late WindowsLaunchAtLogin impl;
    const exe = r'C:\Apps\Knight Rise\knight_rise.exe';

    setUp(() {
      store = _MemoryStore();
      impl = WindowsLaunchAtLogin(store: store, executable: exe);
    });
    tearDown(() => LaunchArguments.values = const []);

    test('writes the quoted executable with --autostart', () async {
      expect(await impl.status(), LaunchAtLoginStatus.disabled);
      expect(await impl.setEnabled(true), LaunchAtLoginStatus.enabled);
      expect(store.values['KnightRise'], r'"C:\Apps\Knight Rise\knight_rise.exe" --autostart');
    });

    test('disabling removes the value', () async {
      await impl.setEnabled(true);
      expect(await impl.setEnabled(false), LaunchAtLoginStatus.disabled);
      expect(store.values, isEmpty);
    });

    test('a stale path counts as disabled and is rewritten on enable', () async {
      store.values['KnightRise'] = r'"D:\old\knight_rise.exe" --autostart';
      expect(await impl.status(), LaunchAtLoginStatus.disabled);
      await impl.setEnabled(true);
      expect(await impl.status(), LaunchAtLoginStatus.enabled);
    });

    test('registry failures are unavailable, never thrown', () async {
      store.failing = true;
      expect(await impl.status(), LaunchAtLoginStatus.unavailable);
      expect(await impl.setEnabled(true), LaunchAtLoginStatus.unavailable);
    });

    test('launchedAtLogin follows --autostart', () async {
      expect(await impl.launchedAtLogin(), isFalse);
      LaunchArguments.values = const ['--autostart'];
      expect(await impl.launchedAtLogin(), isTrue);
    });
  });

  group('WindowsLaunchAtLogin in an MSIX package', () {
    test('is managed by the system and never touches the Run key', () async {
      final store = _MemoryStore()..values['KnightRise'] = 'stale';
      final impl = WindowsLaunchAtLogin(
        store: store,
        executable: r'C:\x\knight_rise.exe',
        packageIdentity: const FixedPackageIdentity(isPackaged: true),
      );
      expect(await impl.status(), LaunchAtLoginStatus.managedBySystem);
      expect(await impl.setEnabled(true), LaunchAtLoginStatus.managedBySystem);
      expect(await impl.setEnabled(false), LaunchAtLoginStatus.managedBySystem);
      expect(store.values, {'KnightRise': 'stale'}, reason: 'virtualized HKCU: no reads or writes');
      store.failing = true;
      expect(await impl.status(), LaunchAtLoginStatus.managedBySystem, reason: 'the store is not even read');
    });

    test('an unpackaged process keeps using the Run key', () async {
      final impl = WindowsLaunchAtLogin(
        store: _MemoryStore(),
        executable: r'C:\x\knight_rise.exe',
        packageIdentity: const FixedPackageIdentity(isPackaged: false),
      );
      expect(await impl.setEnabled(true), LaunchAtLoginStatus.enabled);
    });
  });

  group('FfiPackageIdentity', () {
    test('only APPMODEL_ERROR_NO_PACKAGE means unpackaged', () {
      expect(FfiPackageIdentity.isPackagedResult(15700), isFalse);
      expect(FfiPackageIdentity.isPackagedResult(0), isTrue); // ERROR_SUCCESS
      expect(FfiPackageIdentity.isPackagedResult(122), isTrue); // ERROR_INSUFFICIENT_BUFFER (zero-length probe)
    });
  });

  test('UnsupportedLaunchAtLogin is inert', () async {
    const impl = UnsupportedLaunchAtLogin();
    expect(await impl.status(), LaunchAtLoginStatus.unavailable);
    expect(await impl.setEnabled(true), LaunchAtLoginStatus.unavailable);
    expect(await impl.launchedAtLogin(), isFalse);
  });
}
