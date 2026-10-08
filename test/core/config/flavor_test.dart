import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/config/app_info.dart';
import 'package:knight_rise/core/config/flavor.dart';

void main() {
  test('an explicit FLAVOR define wins, then the native --flavor, then the build mode', () {
    String r(String defined, String native, {bool release = false}) =>
        resolveFlavorName(defined: defined, native: native, release: release);
    expect(r('prod', 'dev'), 'prod');
    expect(r('dev', 'prod', release: true), 'dev');
    expect(r('', 'prod'), 'prod');
    expect(r('', 'dev', release: true), 'dev');
    expect(r('', ''), 'dev');
    expect(r('', '', release: true), 'prod', reason: 'a forgotten flag never ships dev tools');
    expect(r('staging', 'qa', release: true), 'prod', reason: 'unknown names fall back to the build mode');
  });

  test('the compile-time constant follows the same rules for this build', () {
    final expected = resolveFlavorName(
      defined: const String.fromEnvironment('FLAVOR'),
      native: const String.fromEnvironment('FLUTTER_APP_FLAVOR'),
      release: kReleaseMode,
    );
    expect(kDevFlavor ? 'dev' : 'prod', expected);
    expect(Flavor.current.isDev, kDevFlavor);
  });

  test("the settings intents target this flavor's application id", () {
    expect(kAndroidPackageName, kDevFlavor ? 'com.ragheb.knight_rise.dev' : 'com.ragheb.knight_rise');
  });
}
