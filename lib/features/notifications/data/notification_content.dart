import 'dart:ui' show Locale;

import 'package:knight_rise/core/config/background_ids.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Title and body of one notification.
class NotificationContent {
  const NotificationContent({required this.title, required this.body});

  final String title;
  final String body;
}

/// Pure copy builder. Uses a context-free lookup so it also works in
/// background isolates.
abstract final class NotificationCopy {
  static AppLocalizations get defaultL10n => lookupAppLocalizations(const Locale('en'));

  /// Single routine: its own copy. Several: "Knight's call" + labels joined by " + ".
  static NotificationContent build(Set<RoutineType> types, {AppLocalizations? l10n}) {
    final l = l10n ?? defaultL10n;
    final sorted = sortedTypes(types);
    if (sorted.length == 1) {
      return switch (sorted.single) {
        RoutineType.hydration => NotificationContent(title: l.notifHydrationTitle, body: l.notifHydrationBody),
        RoutineType.stretch => NotificationContent(title: l.notifStretchTitle, body: l.notifStretchBody),
        RoutineType.eyeRest => NotificationContent(title: l.notifEyeRestTitle, body: l.notifEyeRestBody),
      };
    }
    return NotificationContent(title: l.notifMergedTitle, body: sorted.map((t) => routineLabel(l, t)).join(' + '));
  }

  static String routineLabel(AppLocalizations l, RoutineType t) => switch (t) {
    RoutineType.hydration => l.routineHydration,
    RoutineType.stretch => l.routineStretch,
    RoutineType.eyeRest => l.routineEyeRest,
  };

  static String channelDescription(AppLocalizations l, RoutineType t) => switch (t) {
    RoutineType.hydration => l.notifChannelHydrationDescription,
    RoutineType.stretch => l.notifChannelStretchDescription,
    RoutineType.eyeRest => l.notifChannelEyeRestDescription,
  };

  static String channelId(RoutineType t) => switch (t) {
    RoutineType.hydration => NotificationChannelIds.hydration,
    RoutineType.stretch => NotificationChannelIds.stretch,
    RoutineType.eyeRest => NotificationChannelIds.eyeRest,
  };

  /// Types in [RoutineType] declaration order.
  static List<RoutineType> sortedTypes(Set<RoutineType> types) =>
      types.toList()..sort((a, b) => a.index.compareTo(b.index));

  /// Channel of the lowest-index routine in [types].
  static String channelFor(Set<RoutineType> types) => channelId(sortedTypes(types).first);
}
