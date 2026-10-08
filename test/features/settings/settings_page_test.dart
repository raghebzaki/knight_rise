import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
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
    final settingsCubit = SettingsCubit(settings, work);
    addTearDown(themeCubit.close);
    addTearDown(settingsCubit.close);
    addTearDown(health.cubit.close);
    useTallView(tester);
    await tester.pumpWidget(
      BlocProvider.value(
        value: themeCubit,
        child: themedApp(SettingsPage(cubit: settingsCubit, healthCubit: health.cubit)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows groups, work-hours summary, device health row and version', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sun–Thu · 09:00–17:00'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const Key('deviceHealthRow'))).enabled, isTrue);
    expect(find.text('All good'), findsOneWidget);
    expect(find.text('Version 1.0.0'), findsOneWidget);
    expect(find.text('Stay Active. Stay Focused.'), findsOneWidget);
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
}
