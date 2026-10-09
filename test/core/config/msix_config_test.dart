import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/config/background_ids.dart';
import 'package:yaml/yaml.dart';

void main() {
  late YamlMap msix;
  late String pubspecVersion;

  setUpAll(() {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    msix = pubspec['msix_config'] as YamlMap;
    pubspecVersion = pubspec['version'] as String;
  });

  test('the package identity is the AppUserModelID', () {
    expect(msix['identity_name'], kWindowsAppUserModelId);
  });

  test('the toast activator is the plugin COM class', () {
    final activator = msix['toast_activator'] as YamlMap;
    expect((activator['clsid'] as String).toUpperCase(), kWindowsToastActivatorGuid.toUpperCase());
    expect(activator['arguments'], isNotEmpty);
    expect(activator['arguments'], isNot(contains('--autostart')), reason: 'a toast must not start the app hidden');
  });

  test('the startup task starts the runner hidden, on by default', () {
    final task = msix['startup_task'] as YamlMap;
    expect(task['enabled'], isTrue);
    expect(task['parameters'], contains('--autostart'));
    expect(task['task_id'], isNotEmpty);
  });

  test('msix_version follows the pubspec version and ends in .0', () {
    final name = pubspecVersion.split('+').first;
    expect(msix['msix_version'], '$name.0');
  });

  test('an offline app declares no capabilities', () {
    expect(msix.containsKey('capabilities'), isFalse);
  });

  test('the package logo exists and no certificate is configured', () {
    expect(File(msix['logo_path'] as String).existsSync(), isTrue);
    expect(msix.containsKey('certificate_path'), isFalse);
    expect(msix.containsKey('certificate_password'), isFalse);
  });
}
