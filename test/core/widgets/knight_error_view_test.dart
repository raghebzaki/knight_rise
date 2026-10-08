import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/widgets/knight_error_view.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('says the data is safe, retries, and shows details in dev builds', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      themedApp(
        Scaffold(
          body: KnightErrorView(onRetry: () => retries++, details: 'db closed'),
        ),
      ),
    );
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Your data is safe. Try again in a moment.'), findsOneWidget);
    expect(find.text('db closed'), findsOneWidget); // tests run as the dev flavor
    await tester.tap(find.byKey(const Key('error-retry')));
    expect(retries, 1);
  });

  testWidgets('the build-error fallback needs no theme or localizations', (tester) async {
    await tester.pumpWidget(const KnightBuildErrorFallback());
    expect(find.text('Something went wrong here. Your data is safe.'), findsOneWidget);
  });
}
