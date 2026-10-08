import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/day_override_repository.dart';

/// Marks `date` (a local calendar date; callers pass today) as a day off.
@injectable
class SetDayOff {
  const SetDayOff(this._overrides);

  final DayOverrideRepository _overrides;

  Future<DayOverride> call(DateTime date) async {
    final o = DayOverride(date: dateOnly(date), kind: DayOverrideKind.off);
    await _overrides.set(o);
    return o;
  }
}

/// "Working late": extends the last window of `date` by `minutes`. Repeated
/// calls accumulate up to `kMaxExtendMinutes`. Replaces a day-off override.
/// A non-positive `minutes` changes nothing and returns the current override
/// (or null).
@injectable
class ExtendWorkDay {
  const ExtendWorkDay(this._overrides);

  final DayOverrideRepository _overrides;

  Future<DayOverride?> call(DateTime date, int minutes) async {
    final day = dateOnly(date);
    final existing = (await _overrides.getFrom(day)).where((o) => dateKey(o.date) == dateKey(day)).firstOrNull;
    if (minutes <= 0) return existing;
    final previous = existing?.kind == DayOverrideKind.extend ? (existing?.extendMinutes ?? 0) : 0;
    final o = DayOverride(
      date: day,
      kind: DayOverrideKind.extend,
      extendMinutes: (previous + minutes).clamp(1, kMaxExtendMinutes),
    );
    await _overrides.set(o);
    return o;
  }
}

/// Removes any override of `date`.
@injectable
class ClearDayOverride {
  const ClearDayOverride(this._overrides);

  final DayOverrideRepository _overrides;

  Future<void> call(DateTime date) => _overrides.clear(dateOnly(date));
}
