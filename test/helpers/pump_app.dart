import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// A [MaterialApp] with the Knight theme and localizations around [home].
Widget themedApp(Widget home) => MaterialApp(
  theme: KnightTheme.build(KnightPalette.midnight),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

/// Tall phone-sized view so long lists are fully built.
void useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Pumps a launcher page whose button pushes [page], so back navigation and
/// `PopScope` behave as in the app.
Future<void> pumpPushed(WidgetTester tester, Widget page) async {
  useTallView(tester);
  await tester.pumpWidget(
    themedApp(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
