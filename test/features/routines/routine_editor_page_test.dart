import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/presentation/routine_editor_cubit.dart';
import 'package:knight_rise/features/routines/presentation/routine_editor_page.dart';
import 'package:knight_rise/features/routines/presentation/routines_cubit.dart';
import 'package:knight_rise/features/routines/presentation/routines_page.dart';

import '../../helpers/fake_launcher.dart';
import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  late FakeRoutineRepository repo;
  late FakeSystemSettingsLauncher launcher;

  setUp(() {
    repo = FakeRoutineRepository();
    launcher = FakeSystemSettingsLauncher();
  });

  Future<RoutineEditorCubit> editor(RoutineType type) async {
    final cubit = RoutineEditorCubit(repo, FakeSettingsRepository(), type);
    addTearDown(cubit.close);
    await cubit.load();
    return cubit;
  }

  Future<void> pumpEditor(WidgetTester tester, RoutineType type) async {
    final cubit = await editor(type);
    await pumpPushed(tester, RoutineEditorPage(type: type, cubit: cubit, launcher: launcher));
  }

  testWidgets('slider moves the interval with a live label, Save persists it', (tester) async {
    await pumpEditor(tester, RoutineType.hydration);
    expect(find.text('Every 45 min'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byKey(const Key('intervalSlider')));
    expect(slider.min, 15);
    expect(slider.max, 120);
    expect(slider.divisions, 21);

    slider.onChanged!(60);
    await tester.pumpAndSettle();
    expect(find.text('Every 60 min'), findsOneWidget);
    expect((await repo.getAll()).first.intervalMinutes, 45); // not saved yet

    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();
    expect((await repo.getAll()).first.intervalMinutes, 60);
    expect(find.byType(RoutineEditorPage), findsNothing);
  });

  testWidgets('hydration target shows the ml total; others do not', (tester) async {
    await pumpEditor(tester, RoutineType.hydration);
    expect(find.text('×250 ml = 2,000 ml'), findsOneWidget);
    await tester.tap(find.byKey(const Key('targetPlus')));
    await tester.pumpAndSettle();
    expect(find.text('9 per day'), findsOneWidget);
    expect(find.text('×250 ml = 2,250 ml'), findsOneWidget);
  });

  testWidgets('stretch has no ml total', (tester) async {
    await pumpEditor(tester, RoutineType.stretch);
    expect(find.byKey(const Key('hydrationTotal')), findsNothing);
    expect(find.text('6 per day'), findsOneWidget);
  });

  testWidgets('mode selector switches the explanation', (tester) async {
    await pumpEditor(tester, RoutineType.eyeRest);
    expect(find.text('The next reminder comes one interval after you complete one.'), findsOneWidget);
    await tester.tap(find.text('Fixed grid'));
    await tester.pumpAndSettle();
    expect(find.text('Reminders stay on a fixed grid from the start of your work hours.'), findsOneWidget);
  });

  testWidgets('Save is disabled until something changes', (tester) async {
    await pumpEditor(tester, RoutineType.hydration);
    expect(tester.widget<TextButton>(find.byKey(const Key('saveButton'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('enabledSwitch')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(find.byKey(const Key('saveButton'))).onPressed, isNotNull);
  });

  testWidgets('back with unsaved changes asks first', (tester) async {
    await pumpEditor(tester, RoutineType.hydration);
    await tester.tap(find.byKey(const Key('targetPlus')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(RoutineEditorPage), findsNothing);
    expect((await repo.getAll()).first.dailyTarget, 8);
  });

  testWidgets('sound row opens the routine channel settings on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpEditor(tester, RoutineType.eyeRest);
      await tester.tap(find.byKey(const Key('soundRow')));
      await tester.pump();
      expect(launcher.channelCalls, ['eye_rest']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('sound row is hidden on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpEditor(tester, RoutineType.hydration);
      expect(find.byKey(const Key('soundRow')), findsNothing);
      expect(find.text('Sound & vibration'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('channel ids match the notification channels', () {
    expect(routineChannelId(RoutineType.hydration), 'hydration');
    expect(routineChannelId(RoutineType.stretch), 'stretch');
    expect(routineChannelId(RoutineType.eyeRest), 'eye_rest');
  });

  testWidgets('RoutinesPage lists routines with summaries and inline switches', (tester) async {
    final cubit = RoutinesCubit(repo);
    addTearDown(cubit.close);
    useTallView(tester);
    await tester.pumpWidget(themedApp(RoutinesPage(cubit: cubit)));
    await tester.pumpAndSettle();
    expect(find.text('Every 45 min · 8/day'), findsOneWidget);
    expect(find.text('Every 60 min · 6/day'), findsOneWidget);
    expect(find.text('Every 20 min · 12/day'), findsOneWidget);

    await tester.tap(find.byKey(const Key('routineSwitch-stretch')));
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsOneWidget);
    expect((await repo.getAll()).firstWhere((r) => r.type == RoutineType.stretch).enabled, isFalse);
  });
}
