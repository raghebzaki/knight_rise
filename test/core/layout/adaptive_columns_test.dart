import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/layout/adaptive_columns.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {double width = 2000}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: child));
  }

  testWidgets('ReadableWidth caps and centres, and leaves narrow windows alone', (tester) async {
    await pump(tester, const ReadableWidth(child: SizedBox.expand(key: Key('c'))));
    expect(tester.getSize(find.byKey(const Key('c'))).width, 720);
    expect(tester.getCenter(find.byKey(const Key('c'))).dx, 1000);
    await pump(tester, const ReadableWidth(child: SizedBox.expand(key: Key('c'))), width: 400);
    expect(tester.getSize(find.byKey(const Key('c'))).width, 400);
  });

  testWidgets('AdaptiveTwoColumn splits by flex with a gutter inside the max width', (tester) async {
    await pump(
      tester,
      const AdaptiveTwoColumn(
        startFlex: 3,
        endFlex: 2,
        start: SizedBox.expand(key: Key('s')),
        end: SizedBox.expand(key: Key('e')),
      ),
    );
    final s = tester.getRect(find.byKey(const Key('s')));
    final e = tester.getRect(find.byKey(const Key('e')));
    expect(e.left - s.right, 24);
    expect(s.width / e.width, closeTo(1.5, 0.001));
    expect(e.right - s.left, kMaxContentWidth);
  });
}
