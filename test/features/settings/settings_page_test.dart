import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/shortcuts/shortcuts_dialog.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/features/settings/presentation/locale_cubit.dart';
import 'package:knight_rise/features/settings/presentation/settings_cubit.dart';
import 'package:knight_rise/features/settings/presentation/settings_page.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/presentation/work_format.dart';
import 'package:knight_rise/l10n/generated/app_localizations_en.dart';

import '../../helpers/fakes.dart';
import '../../helpers/health_fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  late FakeSettingsRepository settings;
  late FakeWorkScheduleRepository work;
  late HealthHarness health;

  setUp(() {
    health = HealthHarness();
    settings = FakeSettingsRepository();
    work = FakeWorkScheduleRepository();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    final themeCubit = ThemeCubit(settings);
    final localeCubit = LocaleCubit(settings);
    final settingsCubit = SettingsCubit(settings, work);
    addTearDown(themeCubit.close);
    addTearDown(localeCubit.close);
    addTearDown(settingsCubit.close);
    addTearDown(health.cubit.close);
    await localeCubit.load();
    useTallView(tester);
    await tester.pumpWidget(
      BlocProvider.value(
        value: themeCubit,
        child: localizedApp(localeCubit, SettingsPage(cubit: settingsCubit, healthCubit: health.cubit)),
      ),
    );
    await tester.pumpAndSettle();
  }

  SegmentedButton<Locale> languageSelector(WidgetTester tester) => tester.widget<SegmentedButton<Locale>>(
    find.descendant(of: find.byKey(const Key('languageRow')), matching: find.byKey(const Key('languageSelector'))),
  );

  testWidgets('shows groups, work-hours summary, device health row and version', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sun–Thu · 09:00–17:00'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const Key('deviceHealthRow'))).enabled, isTrue);
    expect(find.text('All good'), findsOneWidget);
    expect(find.text('Version 1.0.0'), findsOneWidget);
    expect(find.text('Stay Active. Stay Focused.'), findsOneWidget);
  });

  testWidgets('the Keyboard shortcuts row is desktop only and opens the cheat sheet', (tester) async {
    await pumpSettings(tester);
    expect(find.byKey(const Key('keyboardShortcutsRow')), findsNothing); // the test platform is Android
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpSettings(tester);
      await tester.ensureVisible(find.byKey(const Key('keyboardShortcutsRow')));
      await tester.tap(find.byKey(const Key('keyboardShortcutsRow')));
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutsDialog), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutsDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('theme selector writes the variant', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('AMOLED'));
    await tester.pumpAndSettle();
    expect(settings.current.themeVariant, ThemeVariant.amoled);
    await tester.tap(find.text('Midnight'));
    await tester.pumpAndSettle();
    expect(settings.current.themeVariant, ThemeVariant.midnight);
  });

  testWidgets('language row: English is in use on an English device', (tester) async {
    await pumpSettings(tester);
    expect(find.text('LANGUAGE'), findsOneWidget);
    expect(languageSelector(tester).selected, {const Locale('en')});
    expect(directionAt(tester, find.text('Settings')), TextDirection.ltr);
  });

  testWidgets('language row switches to العربية: Arabic copy, RTL, persisted', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();

    expect(settings.current.localeCode, 'ar');
    expect(find.text('الإعدادات'), findsOneWidget, reason: 'Settings, in Arabic');
    expect(find.text('Settings'), findsNothing);
    expect(find.text('اللغة'), findsOneWidget, reason: 'the Language row, in Arabic');
    expect(directionAt(tester, find.text('الإعدادات')), TextDirection.rtl);
    expect(languageSelector(tester).selected, {const Locale('ar')});
    expect(find.text('English'), findsOneWidget, reason: 'the way back stays readable');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(settings.current.localeCode, 'en');
    expect(find.text('Settings'), findsOneWidget);
    expect(directionAt(tester, find.text('Settings')), TextDirection.ltr);
  });

  testWidgets('language switches keep the other settings', (tester) async {
    await settings.save(settings.current.copyWith(streakThresholdPercent: 85, hapticsEnabled: false));
    await pumpSettings(tester);
    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();
    expect(settings.current.streakThresholdPercent, 85);
    expect(settings.current.hapticsEnabled, isFalse);
  });

  testWidgets('recovery switch saves shieldRecoverOnExit', (tester) async {
    await pumpSettings(tester);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('recoverSwitch'))).value, isTrue);
    await tester.tap(find.byKey(const Key('recoverSwitch')));
    await tester.pumpAndSettle();
    expect(settings.current.shieldRecoverOnExit, isFalse);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('recoverSwitch'))).value, isFalse);
  });

  testWidgets('a mixed schedule reads Custom', (tester) async {
    await work.save(
      WorkSchedule(
        days: {
          DateTime.sunday: [TimeWindow.hm(9, 0, 17, 0)],
          DateTime.monday: [TimeWindow.hm(10, 0, 17, 0)],
        },
      ),
    );
    await pumpSettings(tester);
    expect(find.text('Custom'), findsOneWidget);
  });

  group('workScheduleSummary', () {
    final l = AppLocalizationsEn();
    String summary(WorkSchedule s) => workScheduleSummary(l, 'en', s);

    test('contiguous run, scattered days, split shift, none', () {
      expect(summary(WorkSchedule.standard()), 'Sun–Thu · 09:00–17:00');
      final nine = [TimeWindow.hm(9, 0, 17, 0)];
      expect(summary(WorkSchedule(days: {1: nine, 2: nine, 3: nine, 4: nine, 5: nine})), 'Mon–Fri · 09:00–17:00');
      expect(summary(WorkSchedule(days: {7: nine, 2: nine, 4: nine})), 'Sun, Tue, Thu · 09:00–17:00');
      expect(summary(WorkSchedule(days: {1: nine, 2: nine})), 'Mon, Tue · 09:00–17:00');
      final split = [TimeWindow.hm(9, 0, 12, 0), TimeWindow.hm(13, 0, 17, 0)];
      expect(summary(WorkSchedule(days: {1: split, 2: split, 3: split})), 'Mon–Wed · 09:00–12:00, 13:00–17:00');
      expect(summary(const WorkSchedule()), 'No work days');
    });
  });

  testWidgets('device health row counts warnings and errors', (tester) async {
    health.gateway
      ..enabled = false
      ..exactAllowed = false;
    await health.settings.save(health.settings.current.copyWith(precisionTiming: true));
    await pumpSettings(tester);
    expect(find.text('2 issues'), findsOneWidget);
  });

  testWidgets('info-level battery hint does not count as an issue', (tester) async {
    health.platformFake.ignoringBattery = false;
    await pumpSettings(tester);
    expect(find.text('All good'), findsOneWidget);
  });

  testWidgets('streak goal slider shows the goal and saves once the drag ends', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Streak goal: 70%'), findsOneWidget);
    final slider = find.byKey(const Key('streakGoalSlider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    // Drag from the 70 % thumb to the right end of the track.
    final box = tester.getRect(slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveTo(Offset(box.right - 4, box.center.dy));
    await tester.pump();
    expect(find.text('Streak goal: 100%'), findsOneWidget);
    expect(settings.current.streakThresholdPercent, 70); // not saved mid-drag
    await gesture.up();
    await tester.pumpAndSettle();
    expect(settings.current.streakThresholdPercent, 100);
    expect(find.text('Streak goal: 100%'), findsOneWidget);
  });

  testWidgets('haptics switch saves hapticsEnabled', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.byKey(const Key('hapticsSwitch')));
    await tester.pumpAndSettle();
    expect(settings.current.hapticsEnabled, isFalse);
  });
}
