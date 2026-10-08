import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/l10n/generated/app_localizations_en.dart';

/// Hand-written sources under lib/ (no generated code).
List<File> _sources() => [
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
    if (f.path.endsWith('.dart') &&
        !f.path.contains('/generated/') &&
        !RegExp(r'\.(g|freezed|config)\.dart$').hasMatch(f.path))
      f,
];

/// Dev-flavor tools are English-only by design.
bool _devOnly(String path) => path.contains('/gallery/') || path.contains('/diagnostics/');

void main() {
  test('no hard-coded user-facing strings outside the ARB file', () {
    // Text('…'), tooltip: '…', label: '…', semanticsLabel: '…', title: '…'
    final pattern = RegExp(
      // A literal word, or an interpolation followed by words ('${n} minutes').
      r"""(?:\bText\(\s*|\b(?:tooltip|label|semanticsLabel|title|hintText|labelText):\s*)'(?:[A-Za-z]|\$\{[^}]*\}\s+[A-Za-z]{2,})""",
    );
    const allowed = {
      // Dev-flavor-only Diagnostics button.
      'lib/features/cycle/presentation/pages/home_page.dart': ["'Diagnostics'"],
      // Release build-error fallback: rendered where localizations may be missing.
      'lib/core/widgets/knight_error_view.dart': ["'Something went wrong here. Your data is safe.'"],
    };
    // The guard itself catches both forms.
    expect(pattern.hasMatch("Text('Hello')"), isTrue);
    expect(pattern.hasMatch(r"label: '${n} minutes remaining'"), isTrue);
    expect(pattern.hasMatch('Text(l.title)'), isFalse);

    final offenders = <String>[];
    for (final f in _sources()) {
      if (_devOnly(f.path)) continue;
      final source = f.readAsStringSync();
      for (final m in pattern.allMatches(source)) {
        final snippet = source.substring(m.start, (m.start + 80).clamp(0, source.length));
        if (allowed[f.path]?.any(snippet.contains) ?? false) continue;
        offenders.add('${f.path}: ${snippet.split('\n').first}');
      }
    }
    expect(offenders, isEmpty, reason: 'Move these strings to lib/l10n/arb/app_en.arb');
  });

  test('layout is direction-aware (no left/right-only padding or alignment)', () {
    final pattern = RegExp(
      r'EdgeInsets\.fromLTRB\(|EdgeInsets\.only\([^)]*\b(?:left|right):|'
      r'Alignment\.(?:centerLeft|centerRight|topLeft|topRight|bottomLeft|bottomRight)|TextAlign\.(?:left|right)\b',
    );
    final offenders = [
      for (final f in _sources())
        for (final m in pattern.allMatches(f.readAsStringSync())) '${f.path}: ${m[0]}',
    ];
    expect(offenders, isEmpty, reason: 'Use EdgeInsetsDirectional / AlignmentDirectional / TextAlign.start|end');
  });

  test('water amounts use locale number formatting', () {
    final l = AppLocalizationsEn();
    expect(l.waterToday(1250), '1,250 ml today');
    expect(l.waterProgress(1250, 2000), '1,250 / 2,000 ml');
    expect(l.statWaterValue(1800), '1,800 ml');
    expect(l.mlAmount(500), '500 ml');
  });
}
