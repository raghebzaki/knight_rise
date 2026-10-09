import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/layout/window_size.dart';

void main() {
  test('fromWidth follows the Material 3 breakpoints', () {
    final expected = {
      0.0: WindowSizeClass.compact,
      599.9: WindowSizeClass.compact,
      600.0: WindowSizeClass.medium,
      839.9: WindowSizeClass.medium,
      840.0: WindowSizeClass.expanded,
      1199.9: WindowSizeClass.expanded,
      1200.0: WindowSizeClass.large,
      2000.0: WindowSizeClass.large,
    };
    for (final MapEntry(key: width, value: size) in expected.entries) {
      expect(WindowSizeClass.fromWidth(width), size, reason: '$width');
    }
  });

  test('rail from medium, multi-pane from expanded', () {
    expect(WindowSizeClass.values.map((s) => s.usesRail), [false, true, true, true]);
    expect(WindowSizeClass.values.map((s) => s.isMultiPane), [false, false, true, true]);
  });
}
