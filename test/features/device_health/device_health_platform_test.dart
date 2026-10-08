import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/device_health/data/device_health_platform.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kDeviceHealthChannel);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final platform = MethodChannelDeviceHealthPlatform();
  final calls = <String>[];

  void mock(Future<Object?>? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call.method);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('battery optimization maps the boolean answer', () async {
    mock((_) async => true);
    expect(await platform.isIgnoringBatteryOptimizations(), isTrue);
    mock((_) async => false);
    expect(await platform.isIgnoringBatteryOptimizations(), isFalse);
    expect(calls, ['isIgnoringBatteryOptimizations', 'isIgnoringBatteryOptimizations']);
  });

  test('background refresh maps names; unknown values become null', () async {
    for (final (name, expected) in [
      ('available', BackgroundRefresh.available),
      ('denied', BackgroundRefresh.denied),
      ('restricted', BackgroundRefresh.restricted),
      ('weird', null),
    ]) {
      mock((_) async => name);
      expect(await platform.backgroundRefreshStatus(), expected, reason: name);
    }
  });

  test('openAppSettings returns the native result', () async {
    mock((_) async => true);
    expect(await platform.openAppSettings(), isTrue);
    mock((_) async => false);
    expect(await platform.openAppSettings(), isFalse);
  });

  test('a missing plugin gives null / false', () async {
    // No handler registered: invokeMethod throws MissingPluginException.
    expect(await platform.isIgnoringBatteryOptimizations(), isNull);
    expect(await platform.backgroundRefreshStatus(), isNull);
    expect(await platform.openAppSettings(), isFalse);
  });

  test('a PlatformException gives null / false', () async {
    mock((_) async => throw PlatformException(code: 'boom'));
    expect(await platform.isIgnoringBatteryOptimizations(), isNull);
    expect(await platform.backgroundRefreshStatus(), isNull);
    expect(await platform.openAppSettings(), isFalse);
  });
}
