import 'package:knight_rise/features/routines/domain/entities/routine.dart';

/// Route of the guided break screen for [types], e.g.
/// `/break?types=hydration,eyeRest`. Types are written in [RoutineType]
/// order. An empty set maps to the dashboard (`/`).
String breakLocation(Set<RoutineType> types) {
  final sorted = sortedBreakTypes(types);
  if (sorted.isEmpty) return '/';
  return '/break?types=${sorted.map((t) => t.name).join(',')}';
}

/// Parses the `types` query value of `/break`. Unknown names are ignored,
/// duplicates collapse, and the result is in [RoutineType] order; empty when
/// nothing valid remains (the router then redirects to `/`).
List<RoutineType> parseBreakTypes(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final byName = RoutineType.values.asNameMap();
  return sortedBreakTypes({for (final name in raw.split(',')) ?byName[name.trim()]});
}

/// [types] in [RoutineType] declaration order.
List<RoutineType> sortedBreakTypes(Iterable<RoutineType> types) =>
    types.toSet().toList()..sort((a, b) => a.index.compareTo(b.index));

/// Drops a repeated "open break" for the same notification. A cold-start tap
/// can be reported by both `launchAction()` and the foreground callback on some
/// platforms; only the first should push `/break`.
class OpenBreakDeduper {
  OpenBreakDeduper({this.now = DateTime.now, this.window = const Duration(seconds: 10)});

  final DateTime Function() now;
  final Duration window;
  int? _lastId;
  DateTime? _lastAt;

  /// True when [notificationId] should open the break screen; records it.
  bool shouldOpen(int notificationId) {
    final at = now();
    final lastAt = _lastAt;
    if (_lastId == notificationId && lastAt != null && at.difference(lastAt) < window) return false;
    _lastId = notificationId;
    _lastAt = at;
    return true;
  }
}
