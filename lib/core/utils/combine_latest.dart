import 'dart:async';

/// Minimal combineLatest for four streams (avoids pulling in rxdart).
/// Emits once every source has emitted, then on each new value.
Stream<R> combineLatest4<A, B, C, D, R>(
  Stream<A> a,
  Stream<B> b,
  Stream<C> c,
  Stream<D> d,
  R Function(A a, B b, C c, D d) combine,
) {
  late StreamController<R> controller;
  final subs = <StreamSubscription<Object?>>[];
  final values = List<Object?>.filled(4, null);
  final seen = List<bool>.filled(4, false);
  var done = 0;

  void onValue(int i, Object? v) {
    values[i] = v;
    seen[i] = true;
    if (seen.every((s) => s)) {
      controller.add(combine(values[0] as A, values[1] as B, values[2] as C, values[3] as D));
    }
  }

  controller = StreamController<R>(
    onListen: () {
      final sources = <Stream<Object?>>[a, b, c, d];
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
