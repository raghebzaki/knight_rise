import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/screens.dart';

/// Resizes the already-pumped screen to [size] logical px and settles.
Future<void> resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Left edges (x) of the scrollables on screen, left to right.
List<double> columnLefts(WidgetTester tester) =>
    [for (final e in find.byType(ListView).evaluate()) tester.getTopLeft(find.byWidget(e.widget)).dx]..sort();

void main() {
  for (final screen in [Screen.today, Screen.questLog]) {
    group('${screen.name} columns', () {
      for (final (width, columns) in [(400.0, 1), (700.0, 1), (1000.0, 2), (1300.0, 2)]) {
        testWidgets('${width.toInt()} px: $columns column(s)', (tester) async {
          await pumpScreen(tester, screen);
          await resize(tester, Size(width, 900));
          expect(tester.takeException(), isNull);
          final lefts = columnLefts(tester);
          expect(lefts, hasLength(columns));
          if (columns == 2) expect(lefts.last, greaterThan(lefts.first + width * 0.3));
          await unmountScreen(tester);
        });
      }

      testWidgets('RTL mirrors the columns: the start column is on the right', (tester) async {
        await pumpScreen(tester, screen, locale: const Locale('ar'));
        await resize(tester, const Size(1300, 900));
        final lists = find.byType(ListView).evaluate().map((e) => tester.getRect(find.byWidget(e.widget))).toList();
        expect(lists, hasLength(2));
        // The first ListView in tree order is the start column.
        expect(lists.first.left, greaterThan(lists.last.left));
        await unmountScreen(tester);
      });
    });
  }

  group('overflow sweep', () {
    for (final screen in [Screen.today, Screen.questLog, Screen.history]) {
      for (final size in const [Size(400, 640), Size(1300, 900)]) {
        for (final locale in const [Locale('en'), Locale('ar')]) {
          for (final scale in [1.0, 2.0]) {
            testWidgets(
              '${screen.name} ${size.width.toInt()}x${size.height.toInt()} ${locale.languageCode} ${scale}x',
              (tester) async {
                await pumpScreen(tester, screen, locale: locale, textScale: scale);
                await resize(tester, size);
                expect(tester.takeException(), isNull);
                await unmountScreen(tester);
              },
            );
          }
        }
      }
    }
  });

  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets('history ${locale.languageCode} 2x: table with a pinned day has no overflow', (tester) async {
      await pumpScreen(tester, Screen.history, locale: locale, textScale: 2);
      await resize(tester, const Size(1300, 900));
      await tester.tap(find.byKey(const Key('history-table-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('history-row-2026-10-08')));
      await tester.pump();
      expect(find.byKey(const Key('history-pane-pinned')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountScreen(tester);
    });
  }
}
