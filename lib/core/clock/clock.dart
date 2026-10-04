/// Source of "now". Inject this instead of calling `DateTime.now()` so that
/// scheduling logic is testable with a fixed or advancing time.
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Test clock. Mutate [current] or call [advance].
class FixedClock implements Clock {
  FixedClock(this.current);

  DateTime current;

  void advance(Duration d) => current = current.add(d);

  @override
  DateTime now() => current;
}
