import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/utils/combine_latest.dart';

void main() {
  test('emits once all sources have a value, then on every change, in source order', () async {
    final a = StreamController<int>();
    final b = StreamController<String>();
    final c = StreamController<bool>();
    final out = <String>[];
    final sub = combineLatest<String>([a.stream, b.stream, c.stream], (v) => v.join('|')).listen(out.add);

    a.add(1);
    b.add('x');
    await Future<void>.delayed(Duration.zero);
    expect(out, isEmpty);
    c.add(true);
    await Future<void>.delayed(Duration.zero);
    a.add(2);
    c.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(out, ['1|x|true', '2|x|true', '2|x|false']);
    await sub.cancel();
    await a.close();
    await b.close();
    await c.close();
  });

  test('works with a single source, closes when all sources are done, forwards errors', () async {
    final a = StreamController<int>();
    final b = StreamController<int>();
    final out = <int>[];
    final errors = <Object>[];
    final done = Completer<void>();
    combineLatest<int>([
      a.stream,
      b.stream,
    ], (v) => (v[0]! as int) + (v[1]! as int)).listen(out.add, onError: errors.add, onDone: done.complete);
    a.add(1);
    b
      ..add(10)
      ..addError('boom');
    await a.close();
    expect(done.isCompleted, isFalse);
    await b.close();
    await done.future;
    expect(out, [11]);
    expect(errors, ['boom']);

    expect(await combineLatest<int>([Stream.value(5)], (v) => v.single! as int).toList(), [5]);
  });

  test('an empty source list completes immediately', () async {
    expect(await combineLatest<int>(const [], (_) => 1).toList(), isEmpty);
  });

  test('combineLatest4 keeps working with typed sources', () async {
    final r = await combineLatest4<int, String, bool, double, String>(
      Stream.value(1),
      Stream.value('a'),
      Stream.value(true),
      Stream.value(2.5),
      (a, b, c, d) => '$a$b$c$d',
    ).first;
    expect(r, '1atrue2.5');
  });
}
