import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/cycle/presentation/pages/home_page.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

void main() {
  Future<FakeReminderEventRepository> pumpHome(WidgetTester tester, DateTime now) async {
    final events = FakeReminderEventRepository();
    final settings = FakeSettingsRepository();
    final clock = FixedClock(now);
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
              create: (_) => CycleBloc(
                WatchCycleInputs(FakeRoutineRepository(), FakeWorkScheduleRepository(), events, settings),
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
            home: const HomePage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return events;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('shows the quest, a due routine, and claims the break', (tester) async {
    final events = await pumpHome(tester, at(cairo, 2026, 10, 5, 9, 50));

    expect(find.text('KNIGHT RISE'), findsOneWidget);
    expect(find.text("TODAY'S QUEST"), findsOneWidget);
    expect(find.text('DUE NOW'), findsOneWidget);
    expect(find.text('Hydration'), findsWidgets);

    await tester.tap(find.text('Claim break'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // At 09:50 both hydration (09:45) and eye rest (09:20/09:40) are due.
    expect(events.all, hasLength(2));
    expect(events.all.where((e) => e.type == RoutineType.hydration && e.outcome == ReminderOutcome.done), hasLength(1));
    expect(events.all.where((e) => e.type == RoutineType.eyeRest && e.outcome == ReminderOutcome.done), hasLength(1));
    expect(find.text('250 ml today'), findsOneWidget);
    expect(find.text('NEXT UP'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('off duty on the weekend', (tester) async {
    await pumpHome(tester, at(cairo, 2026, 10, 10, 12)); // Saturday
    expect(find.text('Off duty'), findsWidgets);
    expect(find.textContaining('Back on duty'), findsOneWidget);
    await unmount(tester);
  });
}
