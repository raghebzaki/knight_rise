import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

extension RoutineTypeUi on RoutineType {
  IconData get icon => switch (this) {
    RoutineType.hydration => Icons.water_drop_outlined,
    RoutineType.stretch => Icons.accessibility_new_rounded,
    RoutineType.eyeRest => Icons.visibility_outlined,
  };

  String label(AppLocalizations l) => switch (this) {
    RoutineType.hydration => l.routineHydration,
    RoutineType.stretch => l.routineStretch,
    RoutineType.eyeRest => l.routineEyeRest,
  };
}

/// "14:30" today, "Mon 09:00" on another day.
String formatWhen(BuildContext context, DateTime t, DateTime now) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay ? DateFormat.Hm(locale).format(t) : DateFormat('EEE HH:mm', locale).format(t);
}
