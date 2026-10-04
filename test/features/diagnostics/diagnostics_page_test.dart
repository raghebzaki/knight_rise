import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/core/time/device_timezone.dart';
import 'package:knight_rise/features/diagnostics/presentation/diagnostics_cubit.dart';
import 'package:knight_rise/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:knight_rise/features/notifications/domain/pending_reminder.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

class _DeviceTz implements DeviceTimezone {
  @override
  Future<String?> currentId() async => 'Africa/Cairo';
}

void main() {
  testWidgets('shows status, sorted pending list, runs with errors, and runs actions', (tester) async {
    tester.view.physicalSize = const Size(1170, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final gateway = FakeNotificationGateway()
      ..exactAllowed = false
      ..pendingReminderList = [
        PendingReminder(
          id: 22,
          payload: ReminderPayload(
            types: const {RoutineType.stretch, RoutineType.eyeRest},
            fireAt: at(cairo, 2026, 10, 5, 11).toUtc(),
          ),
        ),
        PendingReminder(
          id: 21,
          payload: ReminderPayload(types: const {RoutineType.hydration}, fireAt: at(cairo, 2026, 10, 5, 10).toUtc()),
        ),
      ];
    final settings = FakeSettingsRepository();
    await settings.save(const AppSettings(timezoneId: 'Africa/Cairo', precisionTiming: true));
    final runs = FakeReconcileRunRepository();
    await runs.record(
      ReconcileRun(
        at: at(cairo, 2026, 10, 5, 9, 30),
        trigger: ReconcileTrigger.launch,
        planned: 5,
        added: 4,
        cancelled: 1,
        error: 'boom',
      ),
    );
    final reconciler = FakeScheduleReconciler();
    final cubit = DiagnosticsCubit(
      gateway,
      settings,
      runs,
      reconciler,
      _DeviceTz(),
      FixedClock(at(cairo, 2026, 10, 5, 9, 30)),
      FakeLocationProvider(cairo),
    );
    addTearDown(cubit.close);
    await cubit.start();

    final theme = KnightTheme.build(KnightPalette.midnight);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DiagnosticsPage(cubit: cubit),
      ),
    );
    await tester.pump();

    expect(find.text('Africa/Cairo'), findsNWidgets(2)); // settings + device
    expect(find.text('Pending notifications (2)'.toUpperCase()), findsOneWidget);
    expect(find.text('Mon 10:00'), findsOneWidget);
    expect(find.text('Mon 11:00'), findsOneWidget);
    expect(find.text('Hydration'), findsOneWidget);
    expect(find.text('Quick stretch + Eye rest'), findsOneWidget);
    expect(find.text('#21'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Mon 10:00')).dy,
      lessThan(tester.getTopLeft(find.text('Mon 11:00')).dy),
      reason: 'sorted by fire time',
    );
    expect(find.textContaining('launch'), findsOneWidget);
    expect(find.text('plan 5 / +4 / -1'), findsOneWidget);
    expect(tester.widget<Text>(find.text('boom')).style?.color, theme.colorScheme.error);

    await tester.tap(find.text('Reconcile now'));
    await tester.pump();
    await tester.pump();
    expect(reconciler.calls, hasLength(1));

    await tester.ensureVisible(find.text('Test notification in 1 min'));
    await tester.tap(find.text('Test notification in 1 min'));
    await tester.pump();
    await tester.pump();
    expect(gateway.testScheduled, [at(cairo, 2026, 10, 5, 9, 31)]);
  });
}
