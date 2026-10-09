import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';

double _luminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final p in [KnightPalette.midnight, KnightPalette.amoled]) {
    group('${p.variant.name} palette', () {
      test('text pairs meet WCAG AA (4.5:1)', () {
        final pairs = <String, (Color, Color)>{
          'onSurface/background': (p.onSurface, p.background),
          'onSurface/surface': (p.onSurface, p.surface),
          'onSurfaceVariant/surface': (p.onSurfaceVariant, p.surface),
          'onSurfaceVariant/surfaceHigh': (p.onSurfaceVariant, p.surfaceContainerHigh),
          'onPrimary/primary': (p.onPrimary, p.primary),
          'primary/surface': (p.primary, p.surface),
          'warning/surface': (p.warning, p.surface),
          'success/surface': (p.success, p.surface),
        };
        for (final MapEntry(:key, value: (fg, bg)) in pairs.entries) {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: key);
        }
      });

      test('ThemeData carries the palette and tokens', () {
        final theme = KnightTheme.build(p);
        expect(theme.colorScheme.primary, p.primary);
        expect(theme.scaffoldBackgroundColor, p.background);
        expect(theme.brightness, Brightness.dark);
        expect(theme.extension<KnightTokens>()!.variant, p.variant);
        expect(theme.textTheme.displayLarge!.fontFamily, KnightFonts.display);
        expect(theme.textTheme.headlineMedium!.fontFamily, KnightFonts.title);
        expect(theme.textTheme.bodyLarge!.fontFamily, KnightFonts.body);
      });
    });
  }

  test('AMOLED uses a true-black background', () {
    expect(KnightPalette.amoled.background, const Color(0xFF000000));
  });

  group('splash hand-off', () {
    String hex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

    test('the splash background is the Midnight background, 1:1', () {
      expect(KnightPalette.splashBackground, KnightPalette.midnight.background);
    });

    test('native splash and launch-window colours match it', () {
      final want = '#${hex(KnightPalette.splashBackground)}';
      for (final path in [
        'flutter_native_splash.yaml',
        'flutter_launcher_icons.yaml',
        'android/app/src/main/res/values/colors.xml',
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ]) {
        final colours = RegExp(r'#(?:FF)?([0-9A-Fa-f]{6})\b').allMatches(File(path).readAsStringSync());
        expect(colours, isNotEmpty, reason: path);
        for (final m in colours) {
          expect('#${m[1]!.toUpperCase()}', want, reason: path);
        }
      }
    });
  });

  group('joined scripts (Arabic)', () {
    test('build(joinedScript: true) drops letter spacing from the type scale', () {
      final latin = KnightTheme.build(KnightPalette.midnight).textTheme;
      final arabic = KnightTheme.build(KnightPalette.midnight, joinedScript: true).textTheme;
      expect(latin.headlineMedium!.letterSpacing, greaterThan(0));
      expect(latin.labelLarge!.letterSpacing, greaterThan(0));
      for (final style in [arabic.headlineMedium, arabic.labelLarge, arabic.labelSmall, arabic.bodyMedium]) {
        expect(style!.letterSpacing, 0);
      }
      expect(arabic.headlineMedium!.fontSize, latin.headlineMedium!.fontSize, reason: 'only the tracking changes');
    });

    testWidgets('tracking() is 0 in Arabic and unchanged in English', (tester) async {
      final seen = <String, double>{};
      for (final code in ['en', 'ar']) {
        await tester.pumpWidget(
          Localizations(
            locale: Locale(code),
            delegates: const [DefaultWidgetsLocalizations.delegate],
            child: Builder(
              builder: (context) {
                seen[code] = KnightTheme.tracking(context, 1.6);
                return const SizedBox();
              },
            ),
          ),
        );
      }
      expect(seen, {'en': 1.6, 'ar': 0.0});
    });
  });
}
