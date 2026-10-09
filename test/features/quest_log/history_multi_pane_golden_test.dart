@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/goldens.dart';
import 'history_multi_pane_test.dart' show pumpHistory;

void main() {
  setUpAll(() async {
    await loadAppFonts();
    TolerantGoldenComparator.install();
  });

  // The Arabic golden checks the mirrored layout only: the app uses the
  // system font for Arabic and the test engine has no fallback, so its
  // glyphs render as boxes.
  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets('history multi-pane with a pinned day, ${locale.languageCode}', (tester) async {
      await pumpHistory(tester, locale: locale);
      await tester.tap(find.byKey(const Key('history-table-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('history-row-2026-10-08')));
      await tester.pump(const Duration(seconds: 1));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/history_multi_pane_${locale.languageCode}.png'),
      );
    });
  }
}
