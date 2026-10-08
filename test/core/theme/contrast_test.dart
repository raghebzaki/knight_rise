import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';

/// WCAG 2.x contrast ratio between two opaque colors.
double contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final la = lum(a);
  final lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// OKLab (×100 for ΔE), from sRGB.
List<double> _oklab(List<double> linear) {
  final [r, g, b] = linear;
  double cbrt(double v) => math.pow(v, 1 / 3).toDouble();
  final l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [
    100 * (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s),
    100 * (1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s),
    100 * (0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s),
  ];
}

List<double> _linear(Color c) {
  double ch(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return [ch(c.r), ch(c.g), ch(c.b)];
}

/// Machado et al. (2009) severity-1.0 simulation, as in the dataviz validator.
const _cvd = {
  'protan': [
    [0.152286, 1.052583, -0.204868],
    [0.114503, 0.786281, 0.099216],
    [-0.003882, -0.048116, 1.051998],
  ],
  'deutan': [
    [0.367322, 0.860646, -0.227968],
    [0.280085, 0.672501, 0.047413],
    [-0.011820, 0.042940, 0.968881],
  ],
};

double deltaE(Color a, Color b, {String? cvd}) {
  List<double> sim(Color c) {
    final lin = _linear(c);
    final m = cvd == null ? null : _cvd[cvd]!;
    final v = m == null
        ? lin
        : [for (final row in m) (row[0] * lin[0] + row[1] * lin[1] + row[2] * lin[2]).clamp(0.0, 1.0)];
    return _oklab(v);
  }

  final x = sim(a);
  final y = sim(b);
  return math.sqrt([for (var i = 0; i < 3; i++) math.pow(x[i] - y[i], 2)].reduce((s, v) => s + v));
}

void main() {
  test('the three routine colors are told apart (dataviz checks: normal ≥ 15, CVD ≥ 8 ΔE)', () {
    // Calibration: the old stretch mint measured 12.6 against hydration in the validator.
    expect(deltaE(const Color(0xFF00E5FF), const Color(0xFF2EE6A6)), closeTo(12.6, 0.1));
    for (final p in [KnightPalette.midnight, KnightPalette.amoled]) {
      final routines = {'hydration': p.hydration, 'stretch': p.stretch, 'eyeRest': p.eyeRest};
      final names = routines.keys.toList();
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          final a = routines[names[i]]!;
          final b = routines[names[j]]!;
          final pair = '${names[i]}↔${names[j]}';
          expect(deltaE(a, b), greaterThanOrEqualTo(15), reason: '$pair normal vision');
          expect(deltaE(a, b, cvd: 'protan'), greaterThanOrEqualTo(8), reason: '$pair protan');
          expect(deltaE(a, b, cvd: 'deutan'), greaterThanOrEqualTo(8), reason: '$pair deutan');
        }
      }
    }
  });

  test('routine colors never reuse a status color (status stays reserved)', () {
    for (final p in [KnightPalette.midnight, KnightPalette.amoled]) {
      for (final r in [p.hydration, p.stretch, p.eyeRest]) {
        for (final s in [p.success, p.warning, p.error]) {
          expect(deltaE(r, s), greaterThanOrEqualTo(10));
        }
      }
    }
  });

  for (final (name, p) in [('Midnight', KnightPalette.midnight), ('AMOLED', KnightPalette.amoled)]) {
    group(name, () {
      final grounds = {'background': p.background, 'surface': p.surface};

      test('body text tokens reach 4.5:1 on background and surface (WCAG AA)', () {
        for (final MapEntry(key: ground, value: g) in grounds.entries) {
          for (final MapEntry(key: token, value: c) in {
            'onSurface': p.onSurface,
            'onSurfaceVariant': p.onSurfaceVariant,
            'textMuted': p.textMuted,
          }.entries) {
            expect(contrast(c, g), greaterThanOrEqualTo(4.5), reason: '$token on $ground');
          }
        }
      });

      test('text on raised surfaces (tooltips, tracks) uses onSurfaceVariant: 4.5:1', () {
        expect(contrast(p.onSurfaceVariant, p.surfaceContainerHigh), greaterThanOrEqualTo(4.5));
      });

      test('accent and status colors used as text reach 4.5:1 on surface', () {
        for (final MapEntry(key: token, value: c) in {
          'primary': p.primary,
          'success': p.success,
          'warning': p.warning,
          'error': p.error,
        }.entries) {
          expect(contrast(c, p.surface), greaterThanOrEqualTo(4.5), reason: token);
        }
      });

      test('label on a filled button reaches 4.5:1', () {
        expect(contrast(p.onPrimary, p.primary), greaterThanOrEqualTo(4.5));
      });

      test('graphics (rings, bars, outlines that convey state) reach 3:1 (WCAG 1.4.11)', () {
        for (final MapEntry(key: token, value: c) in {
          'hydration': p.hydration,
          'stretch': p.stretch,
          'eyeRest': p.eyeRest,
          'secondary': p.secondary,
          'outlineStrong': p.outlineStrong,
        }.entries) {
          expect(contrast(c, p.surface), greaterThanOrEqualTo(3), reason: token);
        }
      });
    });
  }
}
