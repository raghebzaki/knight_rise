import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/l10n/generated/app_localizations_ar.dart';
import 'package:knight_rise/l10n/generated/app_localizations_en.dart';

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

/// Dev-flavor tools are English-only by design.
bool _devOnly(String path) => _posix(path).contains('/gallery/') || _posix(path).contains('/diagnostics/');

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
        if (allowed[_posix(f.path)]?.any(snippet.contains) ?? false) continue;
        offenders.add('${_posix(f.path)}: ${snippet.split('\n').first}');
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
        for (final m in pattern.allMatches(f.readAsStringSync())) '${_posix(f.path)}: ${m[0]}',
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

  group('Arabic catalogue', () {
    Map<String, dynamic> arb(String code) =>
        jsonDecode(File('lib/l10n/arb/app_$code.arb').readAsStringSync()) as Map<String, dynamic>;
    Iterable<String> messages(Map<String, dynamic> m) => m.keys.where((k) => !k.startsWith('@'));
    // Placeholder names used in a message ({name} or {name, plural, ...}).
    Set<String> placeholders(String message) =>
        RegExp(r'\{(\w+)(?=[,}])').allMatches(message).map((m) => m[1]!).toSet();

    test('translates every English message, and nothing else', () {
      expect(messages(arb('ar')).toSet(), messages(arb('en')).toSet());
    });

    test('keeps every placeholder of the English message', () {
      final en = arb('en');
      final ar = arb('ar');
      for (final key in messages(en)) {
        expect(placeholders(ar[key] as String), placeholders(en[key] as String), reason: key);
      }
    });

    test('language names read the same in both languages', () {
      final en = AppLocalizationsEn();
      final ar = AppLocalizationsAr();
      expect([ar.languageNameEn, ar.languageNameAr], [en.languageNameEn, en.languageNameAr]);
      expect(en.language, 'Language');
      expect(ar.language, 'اللغة');
    });

    test('knight ranks, alone and in a sentence', () {
      final l = AppLocalizationsAr();
      expect([l.rankPage, l.rankSquire, l.rankKnight, l.rankPaladin], ['مُتدرب', 'مُحارب', 'فارس', 'فارس أسطوري']);
      expect(l.rankNext(4, l.rankKnight), '4 أيام لبلوغ رتبة فارس');
      expect(l.rankUpBody(l.rankSquire, 3), 'ارتقيت إلى رتبة مُحارب بسلسلة من 3 أيام.');
    });

    test('plurals use the Arabic forms, with Latin digits', () {
      final l = AppLocalizationsAr();
      expect(l.streakDays(1), 'سلسلة يوم واحد');
      expect(l.streakDays(2), 'سلسلة يومين');
      expect(l.streakDays(5), 'سلسلة 5 أيام');
      expect(l.streakDays(14), 'سلسلة 14 يومًا');
      expect(l.countdownRemaining(2), 'دقيقتان متبقيتان');
      expect(l.waterToday(1250), '1,250 مل اليوم');
    });
  });
}
