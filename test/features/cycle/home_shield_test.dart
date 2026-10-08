import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/cycle/presentation/pages/home_page.dart';
import 'package:knight_rise/features/notifications/presentation/notification_permission_cubit.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/shield/presentation/shield_cubit.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

void main() {
  late FakeShieldRepository shields;
  late FakeDayOverrideRepository overrides;
  late FakeSettingsRepository settings;

  Future<void> pumpHome(WidgetTester tester, DateTime now) async {
    shields = FakeShieldRepository();
    overrides = FakeDayOverrideRepository();
    settings = FakeSettingsRepository();
    final events = FakeReminderEventRepository();
    final work = FakeWorkScheduleRepository();
    final clock = FixedClock(now);
    final location = FakeLocationProvider(cairo);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepositoryProvider<Clock>.value(
        value: clock,
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => ThemeCubit(settings)),
            BlocProvider(
              create: (_) => NotificationPermissionCubit(FakeNotificationGateway(), FakeScheduleReconciler()),
            ),
            BlocProvider(
              create: (_) => CycleBloc(
                WatchCycleInputs(FakeRoutineRepository(), work, events, settings, shields, overrides),
                const BuildCycleSnapshot(ReminderPlanner()),
                CompleteRoutine(events, settings, clock),
                SnoozeRoutine(events, clock, cairo),
                clock,
                cairo,
              )..add(const CycleStarted()),
            ),
          ],
          child: MaterialApp(
            theme: KnightTheme.build(KnightPalette.midnight),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomePage(
              shieldCubitFactory: () => ShieldCubit(
                StartShield(shields, work, overrides, const ReminderPlanner(), clock, location),
                ExtendShield(shields, clock),
                EndShield(shields, clock),
                SetDayOff(overrides),
                ExtendWorkDay(overrides),
                ClearDayOverride(overrides),
                clock,
                location,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  // The Next-up card may show the same time, so scope to the banner card.
  Finder bannerCountdown(String text) => find.descendant(
    of: find.ancestor(of: find.text('Shield active'), matching: find.byType(KnightCard)),
    matching: find.text(text),
  );

  final monday = at(cairo, 2026, 10, 5, 9, 30);

  testWidgets('gear opens settings (tooltip present)', (tester) async {
    await pumpHome(tester, monday);
    expect(find.byTooltip('Settings'), findsOneWidget);
    await unmount(tester);
  });

  group('Shield entry', () {
    testWidgets('opens a sheet with the presets; Focus starts a 25 min Shield and shows the banner', (tester) async {
      await pumpHome(tester, monday);
      expect(find.text('Shield active'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Shield'));
      await settle(tester);
      expect(find.text('Focus 25 min'), findsOneWidget);
      expect(find.text('Meeting 50 min'), findsOneWidget);
      expect(find.text('Until I turn it off'), findsOneWidget);
      expect(find.text('Custom…'), findsOneWidget);

      await tester.tap(find.text('Focus 25 min'));
      await settle(tester);

      expect(shields.all.single.endAt, monday.add(const Duration(minutes: 25)));
      expect(find.text('Shield active'), findsOneWidget);
      expect(bannerCountdown('25:00'), findsOneWidget);
      expect(find.text('Recovery ping at 09:55'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Shield'), findsNothing);
      await unmount(tester);
    });

    testWidgets('Custom… picks a duration (default 30 min)', (tester) async {
      await pumpHome(tester, monday);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Shield'));
      await settle(tester);
      await tester.tap(find.text('Custom…'));
      await settle(tester);
      expect(find.text('30 min'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await settle(tester);

      expect(shields.all.single.endAt, monday.add(const Duration(minutes: 30)));
      expect(shields.all.single.reason, ShieldReason.custom);
      await unmount(tester);
    });

    testWidgets('hidden off duty, and so are the day chips on a weekend', (tester) async {
      await pumpHome(tester, at(cairo, 2026, 10, 10, 12)); // Saturday
      expect(find.widgetWithText(OutlinedButton, 'Shield'), findsNothing);
      expect(find.text('Day off today'), findsNothing);
      await unmount(tester);
    });
  });

  group('active Shield banner', () {
    Future<void> withShield(WidgetTester tester) async {
      await pumpHome(tester, monday);
      await shields.add(
        ShieldSession(startAt: monday, endAt: monday.add(const Duration(minutes: 10)), reason: ShieldReason.focus),
      );
      await settle(tester);
    }

    testWidgets('shows a countdown; +15 min extends; End stops it', (tester) async {
      await withShield(tester);
      expect(find.text('Shield active'), findsOneWidget);
      expect(bannerCountdown('10:00'), findsOneWidget);

      await tester.tap(find.text('+15 min'));
      await settle(tester);
      expect(shields.all.single.endAt, monday.add(const Duration(minutes: 25)));
      expect(bannerCountdown('25:00'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'End'));
      await settle(tester);
      expect(shields.all.single.endedAt, monday);
      expect(find.text('Shield active'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Shield'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('no recovery hint when the plan has none (Until I turn it off ends at work-window end)', (
      tester,
    ) async {
      await pumpHome(tester, monday);
      await shields.add(
        ShieldSession(startAt: monday, endAt: at(cairo, 2026, 10, 5, 17), reason: ShieldReason.untilOff),
      );
      await settle(tester);
      expect(find.text('Shield active'), findsOneWidget);
      expect(find.textContaining('Recovery ping'), findsNothing);
      await unmount(tester);
    });

    testWidgets('recovery hint shows only with a planned recovery and follows the setting', (tester) async {
      await withShield(tester);
      // A 10 min Shield suppresses nothing, so no recovery is planned.
      expect(find.textContaining('Recovery ping'), findsNothing);
      await unmount(tester);

      await pumpHome(tester, monday);
      await shields.add(
        ShieldSession(startAt: monday, endAt: monday.add(const Duration(minutes: 25)), reason: ShieldReason.focus),
      );
      await settle(tester);
      expect(find.text('Recovery ping at 09:55'), findsOneWidget);
      await settings.save(settings.current.copyWith(shieldRecoverOnExit: false));
      await settle(tester);
      expect(find.textContaining('Recovery ping'), findsNothing);
      await unmount(tester);
    });
  });

  group('today override chips', () {
    testWidgets('Day off asks first; cancel changes nothing, confirm writes and shows an active chip', (tester) async {
      await pumpHome(tester, monday);
      await tester.tap(find.text('Day off today'));
      await settle(tester);
      expect(find.text('Take the day off?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(overrides.all, isEmpty);

      await tester.tap(find.text('Day off today'));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Day off today')));
      await settle(tester);

      expect(overrides.all.single.kind, DayOverrideKind.off);
      expect(overrides.all.single.date, DateTime.utc(2026, 10, 5));
      expect(find.text('Off duty'), findsWidgets);

      await tester.tap(find.byIcon(Icons.close));
      await settle(tester);
      expect(overrides.all, isEmpty);
      await unmount(tester);
    });

    testWidgets('Working late accumulates and clears', (tester) async {
      await pumpHome(tester, monday);
      expect(find.text('Working late +1h'), findsOneWidget);

      await tester.tap(find.text('Working late +1h'));
      await settle(tester);
      expect(find.text('Working late +1h'), findsOneWidget); // now the active label for 60 minutes
      await tester.tap(find.text('Working late +1h'));
      await settle(tester);
      expect(find.text('Working late +2h'), findsOneWidget);
      expect(overrides.all.single.extendMinutes, 120);

      await tester.tap(find.byIcon(Icons.close));
      await settle(tester);
      expect(overrides.all, isEmpty);
      expect(find.text('Working late +1h'), findsOneWidget);
      await unmount(tester);
    });
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
}
