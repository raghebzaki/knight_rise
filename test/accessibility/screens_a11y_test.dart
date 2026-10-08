import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';

import '../helpers/screens.dart';

void main() {
  for (final screen in Screen.values) {
    group(screen.name, () {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('${scale}x text: no overflow or build errors', (tester) async {
          await pumpScreen(tester, screen, textScale: scale);
          expect(tester.takeException(), isNull);
          await unmountScreen(tester);
        });
      }

      testWidgets('RTL: lays out without overflow', (tester) async {
        await pumpScreen(tester, screen, direction: TextDirection.rtl);
        expect(tester.takeException(), isNull);
        await unmountScreen(tester);
      });

      for (final (name, palette) in [('Midnight', KnightPalette.midnight), ('AMOLED', KnightPalette.amoled)]) {
        testWidgets('$name: tap targets (48 dp / 44 pt), labels and text contrast', (tester) async {
          final handle = tester.ensureSemantics();
          await pumpScreen(tester, screen, palette: palette);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
          await unmountScreen(tester);
        });
      }
    });
  }
}
