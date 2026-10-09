import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [path] with forward slashes, so rules and allow-list keys hold on Windows too.
String _posix(String path) => path.replaceAll(r'\', '/');

/// Hand-written sources under lib/ (no generated code).
List<File> _sources() => [
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
    if (f.path.endsWith('.dart') &&
        !_posix(f.path).contains('/generated/') &&
        !RegExp(r'\.(g|freezed|config)\.dart$').hasMatch(f.path))
      f,
];

void main() {
  // Physical (left/right) geometry that must not flip in Arabic. Path -> allowed matches, each with a reason.
  // Currently empty: the Knight Rise UI has no genuinely physical layout (the progress ring paints from its center
  // and the charts are drawn by direction-aware widgets).
  const allowed = <String, List<String>>{};

  // Asymmetric or physical-side APIs that have a Directional twin. The older rule in source_rules_test.dart covers
  // EdgeInsets / Alignment / TextAlign; this one covers the rest.
  final pattern = RegExp(
    r'\bPositioned\((?:(?!child:)[\s\S])*?\b(?:left|right):|'
    r'BorderRadius\.only\(|Border\.only\([^)]*\b(?:left|right):|\bAlignment\(|FractionalOffset|'
    r'Icons\.(?:arrow_back|arrow_forward|arrow_left|arrow_right|keyboard_arrow_(?:left|right)|navigate_(?:before|next))\b',
  );

  test('the guard catches each physical API', () {
    for (final bad in [
      'Positioned(left: 1, child: x)',
      'Positioned(\n top: 1,\n right: 2,\n child: x)',
      'BorderRadius.only(topLeft: r)',
      'Border.only(left: s)',
      'Alignment(-1, 0)',
      'Icons.arrow_back',
      'Icons.navigate_next',
    ]) {
      expect(pattern.hasMatch(bad), isTrue, reason: bad);
    }
    for (final ok in [
      'PositionedDirectional(start: 1, child: x)',
      'Positioned.fill(child: x)',
      'Positioned(top: 1, child: Foo(left: 1))',
      'BorderRadiusDirectional.only(topStart: r)',
      'Icons.arrow_back_ios_new',
      'Icons.chevron_right', // matchTextDirection: true, mirrors itself
      'Icons.adaptive.arrow_back',
    ]) {
      expect(pattern.hasMatch(ok), isFalse, reason: ok);
    }
  });

  test('layout geometry is directional (RTL safe)', () {
    final offenders = <String>[];
    for (final f in _sources()) {
      final source = f.readAsStringSync();
      for (final m in pattern.allMatches(source)) {
        final text = m[0]!;
        if (allowed[_posix(f.path)]?.any(text.contains) ?? false) continue;
        offenders.add('${_posix(f.path)}: ${text.split('\n').first}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Use PositionedDirectional / BorderRadiusDirectional / AlignmentDirectional / Icons.adaptive.*',
    );
  });
}
