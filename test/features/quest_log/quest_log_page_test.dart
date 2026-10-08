import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_page.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/l10n/generated/app_localizations_en.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/quest_log_harness.dart';
import '../../helpers/tz.dart';

DateTime d(int n) => DateTime.utc(2026, 10, n);

void main() {
  final l = AppLocalizationsEn();

  Future<void> pumpPage(WidgetTester tester, QuestLogHarness h) async {
    useTallView(tester);
    await tester.pumpWidget(themedApp(QuestLogPage(cubitFactory: h.cubit)));
    await tester.pump();
    await tester.pump();
  }

  /// Closes the cubit (and its midnight timer) before the test ends.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  ReminderEvent done(RoutineType t, int h, {int? ml}) => ReminderEvent(
    type: t,
    outcome: ReminderOutcome.done,
    at: at(cairo, 2026, 10, 12, h),
    waterMl: t == RoutineType.hydration ? (ml ?? 250) : null,
  );

  testWidgets('shows the rings, rank, streak, routine progress and focus time', (tester) async {
    final h = QuestLogHarness(
      now: at(cairo, 2026, 10, 12, 11),
      history: [
        for (final n in [4, 5, 6, 7, 8, 11]) pastDay(d(n)),
        pastDay(d(9), workDay: false),
        pastDay(d(10), workDay: false),
      ],
    );
    await h.events.add(done(RoutineType.hydration, 9, ml: 500));
    await h.events.add(done(RoutineType.stretch, 10));
    await h.shields.add(
      ShieldSession(
        startAt: at(cairo, 2026, 10, 12, 9),
        endAt: at(cairo, 2026, 10, 12, 10, 15),
        reason: ShieldReason.focus,
      ),
    );
    await pumpPage(tester, h);

    expect(find.text('QUEST LOG'), findsOneWidget);
    // (500/2000 + 1/6 + 0/12) / 3 = 13.9 %
    expect(find.text('14%'), findsOneWidget);
    expect(find.text('SQUIRE'), findsOneWidget);
    expect(find.text('6-day streak'), findsOneWidget);
    expect(find.text('Best: 6 days · 1 more day to Knight'), findsOneWidget);
    expect(find.text('Reach 70% of every routine to extend your streak.'), findsOneWidget);

    final hydration = find.byKey(const Key('quest-routine-hydration'));
    expect(find.descendant(of: hydration, matching: find.text('500 / 2000 ml')), findsOneWidget);
    expect(find.descendant(of: hydration, matching: find.text('Last at 09:00')), findsOneWidget);
    final stretch = find.byKey(const Key('quest-routine-stretch'));
    expect(find.descendant(of: stretch, matching: find.text('1 / 6')), findsOneWidget);
    final eyeRest = find.byKey(const Key('quest-routine-eyeRest'));
    expect(find.descendant(of: eyeRest, matching: find.text(l.questNotYet)), findsOneWidget);

    expect(find.text('500 ml today'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('focus-today'))).data, '1 h 15 min');
    expect(tester.widget<Text>(find.byKey(const Key('focus-week'))).data, '1 h 15 min');

    // Screen readers get each ring's value.
    expect(
      find.bySemanticsLabel(RegExp('Hydration 500 / 2000 ml, Quick stretch 1 / 6, Eye rest 0 / 12')),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('no history: Page rank, no streak yet', (tester) async {
    await pumpPage(tester, QuestLogHarness(now: at(cairo, 2026, 10, 12, 11)));
    expect(find.text('PAGE'), findsOneWidget);
    expect(find.text('No streak yet'), findsOneWidget);
    expect(find.text('Best: 0 days · 3 more days to Squire'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('focus-today'))).data, '0 min');
    await unmount(tester);
  });

  testWidgets('a water chip logs that amount, offers Undo for 5 s, and Undo removes it', (tester) async {
    final h = QuestLogHarness(now: at(cairo, 2026, 10, 12, 11));
    await pumpPage(tester, h);

    await tester.tap(find.byKey(const Key('water-500')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750)); // entrance animation
    expect(h.events.all.single.waterMl, 500);
    expect(find.text('Logged 500 ml'), findsOneWidget);
    expect(find.text('500 ml today'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump();
    expect(h.events.all, isEmpty);
    expect(find.text('0 ml today'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the Undo SnackBar goes away by itself after 5 s', (tester) async {
    final h = QuestLogHarness(now: at(cairo, 2026, 10, 12, 11));
    await pumpPage(tester, h);
    await tester.tap(find.byKey(const Key('water-150')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750)); // entrance animation
    expect(find.text('Logged 150 ml'), findsOneWidget);

    await tester.pump(kWaterUndoWindow);
    await tester.pump(const Duration(seconds: 1)); // exit animation
    expect(find.text('Logged 150 ml'), findsNothing);
    expect(h.events.all.single.waterMl, 150); // kept
    await unmount(tester);
  });

  testWidgets('today qualified: the streak line says so and counts today', (tester) async {
    final h = QuestLogHarness(now: at(cairo, 2026, 10, 12, 16), history: [pastDay(d(11))]);
    for (final r in Routine.defaults) {
      for (var i = 0; i < r.dailyTarget; i++) {
        await h.events.add(done(r.type, 10));
      }
    }
    await pumpPage(tester, h);
    expect(find.text(l.questQualified), findsOneWidget);
    expect(find.text('2-day streak'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a rest day says the streak is safe', (tester) async {
    await pumpPage(tester, QuestLogHarness(now: at(cairo, 2026, 10, 9, 11))); // Friday
    expect(find.text(l.questRestDay), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('hydration disabled: no water logger, card marked disabled', (tester) async {
    final routines = [
      for (final r in Routine.defaults)
        if (r.type == RoutineType.hydration) r.copyWith(enabled: false) else r,
    ];
    await pumpPage(tester, QuestLogHarness(now: at(cairo, 2026, 10, 12, 11), routines: routines));
    expect(find.byKey(const Key('water-250')), findsNothing);
    final hydration = find.byKey(const Key('quest-routine-hydration'));
    expect(find.descendant(of: hydration, matching: find.text(l.questDisabled)), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('day 1: a clean-slate card that goes away after the first action', (tester) async {
    final h = QuestLogHarness(now: at(cairo, 2026, 10, 12, 11));
    await pumpPage(tester, h);
    expect(find.byKey(const Key('quest-clean-slate')), findsOneWidget);
    expect(find.text(l.questCleanSlateTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('water-250')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('quest-clean-slate')), findsNothing);
    await tester.pump(kWaterUndoWindow + const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('no clean slate once there is history', (tester) async {
    await pumpPage(tester, QuestLogHarness(now: at(cairo, 2026, 10, 12, 11), history: [pastDay(d(11))]));
    expect(find.byKey(const Key('quest-clean-slate')), findsNothing);
    await unmount(tester);
  });

  testWidgets('a rank-up shows the celebration once and records it', (tester) async {
    final h = QuestLogHarness(
      now: at(cairo, 2026, 10, 12, 16),
      history: [
        for (final n in [4, 5, 6, 7, 8, 11]) pastDay(d(n)),
        pastDay(d(9), workDay: false),
        pastDay(d(10), workDay: false),
      ],
    );
    for (final r in Routine.defaults) {
      for (var i = 0; i < r.dailyTarget; i++) {
        await h.events.add(done(r.type, 10));
      }
    }
    await pumpPage(tester, h);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('rank-up-dialog')), findsOneWidget);
    expect(find.text('RANK UP!'), findsOneWidget);
    expect(find.text('You rose to Knight with a 7-day streak.'), findsOneWidget);
    expect(h.settings.current.rankCelebratedOn, d(12));

    await tester.tap(find.text('Onward'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rank-up-dialog')), findsNothing);
    expect(find.text('KNIGHT'), findsOneWidget);
    await unmount(tester);
  });
}
