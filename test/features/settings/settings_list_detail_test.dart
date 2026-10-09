import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/platform/system_settings_launcher.dart';
import 'package:knight_rise/core/router/app_router.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/device_health/presentation/device_health_cubit.dart';
import 'package:knight_rise/features/device_health/presentation/device_health_page.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/presentation/routine_editor_cubit.dart';
import 'package:knight_rise/features/routines/presentation/routine_editor_page.dart';
import 'package:knight_rise/features/routines/presentation/routines_cubit.dart';
import 'package:knight_rise/features/routines/presentation/routines_page.dart';
import 'package:knight_rise/features/settings/presentation/locale_cubit.dart';
import 'package:knight_rise/features/settings/presentation/settings_cubit.dart';
import 'package:knight_rise/features/settings/presentation/settings_page.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/work_hours/presentation/work_hours_cubit.dart';
import 'package:knight_rise/features/work_hours/presentation/work_hours_page.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';
import 'package:knight_rise/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_launcher.dart';
import '../../helpers/fakes.dart';
import '../../helpers/health_fakes.dart';

void main() {
  late FakeSettingsRepository settings;
  final en = AppLocalizationsEn();

  setUp(() {
    settings = FakeSettingsRepository();
    final routines = FakeRoutineRepository();
    final work = FakeWorkScheduleRepository();
    getIt
      ..registerFactory<SettingsCubit>(() => SettingsCubit(settings, work))
      ..registerFactory<DeviceHealthCubit>(() => HealthHarness().cubit)
      ..registerFactory<RoutinesCubit>(() => RoutinesCubit(routines))
      ..registerFactory<WorkHoursCubit>(() => WorkHoursCubit(work))
      ..registerFactoryParam<RoutineEditorCubit, RoutineType, void>((t, _) => RoutineEditorCubit(routines, settings, t))
      ..registerSingleton<SystemSettingsLauncher>(FakeSystemSettingsLauncher());
  });

  tearDown(getIt.reset);

  void resize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
  }

  Future<void> pumpAt(
    WidgetTester tester,
    String location, {
    Size size = const Size(1300, 900),
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    resize(tester, size);
    addTearDown(tester.view.reset);
    final theme = ThemeCubit(settings);
    addTearDown(theme.close);
    final localeCubit = LocaleCubit(settings);
    addTearDown(localeCubit.close);
    final router = buildRouter(initialLocation: location);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: theme),
          BlocProvider.value(value: localeCubit),
        ],
        child: MaterialApp.router(
          theme: KnightTheme.build(KnightPalette.midnight),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool selected(WidgetTester tester, String key) => tester.widget<ListTile>(find.byKey(Key(key))).selected;
  final backArrow = find.byType(BackButton);

  for (final size in const [Size(1300, 900), Size(1000, 800)]) {
    group('wide ${size.width.toInt()}', () {
      testWidgets('/settings shows the list and the placeholder', (tester) async {
        await pumpAt(tester, '/settings', size: size);
        expect(find.byKey(const Key('routinesRow')), findsOneWidget);
        expect(find.text(en.settingsSelectSection), findsOneWidget);
        expect(selected(tester, 'routinesRow'), isFalse);
        expect(backArrow, findsNothing);
      });

      testWidgets('selecting replaces the detail without a back arrow', (tester) async {
        await pumpAt(tester, '/settings', size: size);
        await tester.tap(find.byKey(const Key('routinesRow')));
        await tester.pumpAndSettle();
        expect(find.byType(RoutinesPage), findsOneWidget);
        expect(selected(tester, 'routinesRow'), isTrue);
        expect(backArrow, findsNothing);
        expect(find.text(en.settingsSelectSection), findsNothing);

        await tester.tap(find.byKey(const Key('workHoursRow')));
        await tester.pumpAndSettle();
        expect(find.byType(WorkHoursPage), findsOneWidget);
        expect(find.byType(RoutinesPage), findsNothing);
        expect(selected(tester, 'workHoursRow'), isTrue);
        expect(selected(tester, 'routinesRow'), isFalse);
        expect(backArrow, findsNothing);

        await tester.scrollUntilVisible(
          find.byKey(const Key('deviceHealthRow')),
          200,
          scrollable: find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable)).first,
        );
        await tester.ensureVisible(find.byKey(const Key('deviceHealthRow')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('deviceHealthRow')));
        await tester.pumpAndSettle();
        expect(find.byType(DeviceHealthPage), findsOneWidget);
        expect(selected(tester, 'deviceHealthRow'), isTrue);
      });

      testWidgets('a deep link opens the editor in the pane; its back goes to the routines', (tester) async {
        await pumpAt(tester, '/settings/routines/eyeRest', size: size);
        expect(find.byType(RoutineEditorPage), findsOneWidget);
        expect(find.byKey(const Key('routinesRow')), findsOneWidget);
        expect(selected(tester, 'routinesRow'), isTrue);
        await tester.tap(backArrow);
        await tester.pumpAndSettle();
        expect(find.byType(RoutineEditorPage), findsNothing);
        expect(find.byType(RoutinesPage), findsOneWidget);
        await tester.tap(find.byKey(const Key('routine-stretch')));
        await tester.pumpAndSettle();
        expect(tester.widget<RoutineEditorPage>(find.byType(RoutineEditorPage)).type, RoutineType.stretch);
      });

      testWidgets('a dirty editor asks before switching items', (tester) async {
        await pumpAt(tester, '/settings/routines/eyeRest', size: size);
        await tester.tap(find.byKey(const Key('targetPlus')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('workHoursRow')));
        await tester.pumpAndSettle();
        expect(find.text(en.routineEditorDiscardTitle), findsOneWidget);
        await tester.tap(find.text(en.routineEditorKeepEditing));
        await tester.pumpAndSettle();
        expect(find.byType(RoutineEditorPage), findsOneWidget);
        expect(find.byType(WorkHoursPage), findsNothing);

        await tester.tap(find.byKey(const Key('workHoursRow')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(en.routineEditorDiscard));
        await tester.pumpAndSettle();
        expect(find.byType(WorkHoursPage), findsOneWidget);
        expect(find.byType(RoutineEditorPage), findsNothing);
      });
    });
  }

  testWidgets('arabic: the list pane is on the right', (tester) async {
    await pumpAt(tester, '/settings', locale: const Locale('ar'));
    final list = tester.getCenter(find.byKey(const Key('routinesRow')));
    final placeholder = tester.getCenter(
      find.text(AppLocalizations.of(tester.element(find.byType(SettingsPage))).settingsSelectSection),
    );
    expect(list.dx, greaterThan(placeholder.dx));
  });

  testWidgets('english: the list pane is on the left', (tester) async {
    await pumpAt(tester, '/settings');
    expect(
      tester.getCenter(find.byKey(const Key('routinesRow'))).dx,
      lessThan(tester.getCenter(find.text(en.settingsSelectSection)).dx),
    );
  });

  testWidgets('compact keeps push navigation with back arrows', (tester) async {
    await pumpAt(tester, '/settings', size: const Size(400, 800));
    expect(find.text(en.settingsSelectSection), findsNothing);
    await tester.tap(find.byKey(const Key('workHoursRow')));
    await tester.pumpAndSettle();
    expect(find.byType(WorkHoursPage), findsOneWidget);
    expect(find.byKey(const Key('workHoursRow')), findsNothing);
    expect(backArrow, findsOneWidget);
    await tester.tap(backArrow);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workHoursRow')), findsOneWidget);
  });

  testWidgets('resizing keeps the location', (tester) async {
    await pumpAt(tester, '/settings/work-hours', size: const Size(400, 800));
    expect(find.byType(WorkHoursPage), findsOneWidget);
    expect(find.byKey(const Key('workHoursRow')), findsNothing);

    resize(tester, const Size(1300, 900));
    await tester.pumpAndSettle();
    expect(find.byType(WorkHoursPage), findsOneWidget);
    expect(find.byKey(const Key('workHoursRow')), findsOneWidget);
    expect(selected(tester, 'workHoursRow'), isTrue);
    expect(backArrow, findsNothing);

    resize(tester, const Size(400, 800));
    await tester.pumpAndSettle();
    expect(find.byType(WorkHoursPage), findsOneWidget);
    expect(find.byKey(const Key('workHoursRow')), findsNothing);
    expect(backArrow, findsOneWidget);
    await tester.tap(backArrow);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workHoursRow')), findsOneWidget);
  });

  group('no overflow', () {
    const locations = [
      '/settings',
      '/settings/work-hours',
      '/settings/device-health',
      '/settings/routines',
      '/settings/routines/hydration',
    ];
    for (final size in const [Size(400, 640), Size(1300, 900)]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        for (final scale in const [1.0, 2.0]) {
          testWidgets('${size.width.toInt()} ${locale.languageCode} x$scale', (tester) async {
            for (final location in locations) {
              await pumpAt(tester, location, size: size, locale: locale, textScale: scale);
              expect(tester.takeException(), isNull, reason: location);
            }
          });
        }
      }
    }
  });
}
