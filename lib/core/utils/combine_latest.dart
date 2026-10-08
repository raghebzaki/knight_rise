import 'dart:async';

/// Minimal combineLatest over any number of streams (avoids pulling in rxdart).
/// Emits once every source has emitted, then on each new value. [combine]
/// receives the latest values in the order of [sources]. Closes when all
/// sources are done.
Stream<R> combineLatest<R>(List<Stream<Object?>> sources, R Function(List<Object?> values) combine) {
  late StreamController<R> controller;
  final subs = <StreamSubscription<Object?>>[];
  final values = List<Object?>.filled(sources.length, null);
  final seen = List<bool>.filled(sources.length, false);
  var done = 0;

  void onValue(int i, Object? v) {
    values[i] = v;
    seen[i] = true;
    if (seen.every((s) => s)) {
      controller.add(combine(List<Object?>.unmodifiable(values)));
    }
  }

  controller = StreamController<R>(
    onListen: () {
      if (sources.isEmpty) {
        unawaited(controller.close());
        return;
      }
      for (var i = 0; i < sources.length; i++) {
        subs.add(
          sources[i].listen(
            (v) => onValue(i, v),
            onError: controller.addError,
            onDone: () {
              if (++done == sources.length) unawaited(controller.close());
            },
          ),
        );
      }
    },
    onPause: () {
      for (final s in subs) {
        s.pause();
      }
    },
    onResume: () {
      for (final s in subs) {
        s.resume();
      }
    },
    onCancel: () => Future.wait(subs.map((s) => s.cancel())),
  );
  return controller.stream;
}

/// Four-stream convenience over [combineLatest] that keeps the sources typed.
Stream<R> combineLatest4<A, B, C, D, R>(
  Stream<A> a,
  Stream<B> b,
  Stream<C> c,
  Stream<D> d,
  R Function(A a, B b, C c, D d) combine,
) => combineLatest<R>([a, b, c, d], (v) => combine(v[0] as A, v[1] as B, v[2] as C, v[3] as D));
