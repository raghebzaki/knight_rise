@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/splash/presentation/animated_splash.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/goldens.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    TolerantGoldenComparator.install();
  });

  Future<void> pumpSplash(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KnightTheme.build(KnightPalette.midnight),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AnimatedSplash(onFinished: () {}),
      ),
    );
    // Decode the shield and glow layers for real.
    final context = tester.element(find.byType(AnimatedSplash));
    await tester.runAsync(() async {
      await precacheImage(const AssetImage(kSplashMarkAsset), context);
      await precacheImage(const AssetImage(kSplashGlowAsset), context);
    });
  }

  for (final (name, at) in [
    ('entering', const Duration(milliseconds: 300)),
    ('crest_glow', const Duration(milliseconds: 850)),
    ('final', kSplashDuration),
  ]) {
    testWidgets('splash $name', (tester) async {
      await pumpSplash(tester);
      await tester.pump(at);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/splash_$name.png'));
      await tester.pump(kSplashDuration);
    });
  }
}
