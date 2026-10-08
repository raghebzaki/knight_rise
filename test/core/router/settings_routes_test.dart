import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/config/app_info.dart';
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
import 'package:knight_rise/features/settings/presentation/settings_cubit.dart';
import 'package:knight_rise/features/settings/presentation/settings_page.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/work_hours/presentation/work_hours_cubit.dart';
import 'package:knight_rise/features/work_hours/presentation/work_hours_page.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/fake_launcher.dart';
import '../../helpers/fakes.dart';
import '../../helpers/health_fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  late FakeSettingsRepository settings;

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

  Future<void> pumpAt(WidgetTester tester, String location) async {
    useTallView(tester);
    final theme = ThemeCubit(settings);
    addTearDown(theme.close);
    final router = buildRouter(initialLocation: location);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      BlocProvider.value(
        value: theme,
        child: MaterialApp.router(
          theme: KnightTheme.build(KnightPalette.midnight),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('routineTypeFromParam parses the three names only', () {
    expect(routineTypeFromParam('hydration'), RoutineType.hydration);
    expect(routineTypeFromParam('eyeRest'), RoutineType.eyeRest);
    expect(routineTypeFromParam('bogus'), isNull);
    expect(routineTypeFromParam(null), isNull);
  });

  testWidgets('/settings, /settings/work-hours, /settings/routines resolve', (tester) async {
    await pumpAt(tester, '/settings');
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('workHoursRow')));
    await tester.pumpAndSettle();
    expect(find.byType(WorkHoursPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routinesRow')));
    await tester.pumpAndSettle();
    expect(find.byType(RoutinesPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('routine-stretch')));
    await tester.pumpAndSettle();
    expect(find.byType(RoutineEditorPage), findsOneWidget);
    expect(tester.widget<RoutineEditorPage>(find.byType(RoutineEditorPage)).type, RoutineType.stretch);
  });

  testWidgets('/settings/routines/eyeRest opens that editor', (tester) async {
    await pumpAt(tester, '/settings/routines/eyeRest');
    expect(tester.widget<RoutineEditorPage>(find.byType(RoutineEditorPage)).type, RoutineType.eyeRest);
  });

  testWidgets('an invalid routine type redirects to /settings/routines', (tester) async {
    await pumpAt(tester, '/settings/routines/bogus');
    expect(find.byType(RoutineEditorPage), findsNothing);
    expect(find.byType(RoutinesPage), findsOneWidget);
  });

  testWidgets('/settings/device-health opens the Device health page', (tester) async {
    await pumpAt(tester, '/settings/device-health');
    expect(find.byType(DeviceHealthPage), findsOneWidget);
    expect(ReservedRoutes.deviceHealth, '/settings/device-health');
  });
}
