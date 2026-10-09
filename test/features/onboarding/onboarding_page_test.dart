import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/features/notifications/presentation/notification_permission_cubit.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_cubit.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_page.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/settings/presentation/locale_cubit.dart';

import '../../helpers/fakes.dart';
import '../../helpers/health_fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  late FakeRoutineRepository routines;
  late FakeWorkScheduleRepository schedule;
  late FakeSettingsRepository settings;
  late FakeScheduleReconciler reconciler;
  late FakeNotificationGateway gateway;
  late FakeLaunchAtLogin launch;

  setUp(() {
    routines = FakeRoutineRepository();
    schedule = FakeWorkScheduleRepository();
    settings = FakeSettingsRepository();
    reconciler = FakeScheduleReconciler();
    gateway = FakeNotificationGateway()..enabled = false;
    launch = FakeLaunchAtLogin();
    getIt.registerFactory<OnboardingCubit>(() => OnboardingCubit(routines, schedule, settings, reconciler, launch));
  });

  tearDown(getIt.reset);

  Future<void> pumpPage(WidgetTester tester, {LocaleCubit? locale}) async {
    useTallView(tester);
    final permission = NotificationPermissionCubit(gateway, reconciler);
    addTearDown(permission.close);
    await permission.check();
    const page = OnboardingPage();
    await tester.pumpWidget(
      BlocProvider.value(value: permission, child: locale == null ? themedApp(page) : localizedApp(locale, page)),
    );
    await tester.pumpAndSettle();
  }

  Future<LocaleCubit> pumpWithLanguage(WidgetTester tester) async {
    final locale = LocaleCubit(settings);
    addTearDown(locale.close);
    await locale.load();
    await pumpPage(tester, locale: locale);
    return locale;
  }

  OnboardingCubit cubitOf(WidgetTester tester) => tester.element(find.byType(Scaffold)).read<OnboardingCubit>();

  Future<void> primary(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('onboarding-primary')));
    await tester.pumpAndSettle();
  }

  bool primaryEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('onboarding-primary'))).onPressed != null;

  Color segmentColor(WidgetTester tester, int i) =>
      (tester.widget<AnimatedContainer>(find.byKey(Key('progress-segment-$i'))).decoration! as BoxDecoration).color!;

  testWidgets('welcome step shows the oath, a 4-segment progress bar and Begin', (tester) async {
    await pumpPage(tester);
    expect(find.text('KNIGHT RISE'), findsOneWidget);
    expect(find.text('Every hour, a knight rises: water, stretch, rest your eyes.'), findsOneWidget);
    expect(find.text('Begin'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-back')), findsNothing);
    expect(find.byKey(const Key('progress-segment-3')), findsOneWidget);
    expect(segmentColor(tester, 0), isNot(segmentColor(tester, 1)));
  });

  group('language (step 0)', () {
    testWidgets('the welcome step opens with the language selector, on the device language', (tester) async {
      await pumpWithLanguage(tester);
      expect(find.byKey(const Key('languageSelector')), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);
      final selector = tester.widget<SegmentedButton<Locale>>(find.byKey(const Key('languageSelector')));
      expect(selector.selected, {const Locale('en')}, reason: 'the test device is en-US');
      expect(settings.current.localeCode, isNull, reason: 'nothing is stored until a choice is made');
    });

    testWidgets('choosing العربية switches the whole flow to Arabic and RTL at once, and persists it', (tester) async {
      final locale = await pumpWithLanguage(tester);
      expect(directionAt(tester, find.text('Begin')), TextDirection.ltr);

      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();

      expect(locale.state, const Locale('ar'));
      expect(settings.current.localeCode, 'ar');
      expect(find.text('ابدأ'), findsOneWidget, reason: 'Begin, in Arabic');
      expect(find.text('Begin'), findsNothing);
      expect(directionAt(tester, find.text('ابدأ')), TextDirection.rtl);
      expect(tester.widget<SegmentedButton<Locale>>(find.byKey(const Key('languageSelector'))).selected, {
        const Locale('ar'),
      });

      // The draft and its step survive the switch; the next steps read in Arabic.
      await primary(tester);
      expect(cubitOf(tester).state.step, OnboardingStep.routines);
      expect(find.text('روتيناتك'), findsOneWidget, reason: 'Your routines, in Arabic');
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching back to English restores LTR and the English copy', (tester) async {
      await settings.save(settings.current.copyWith(localeCode: 'ar'));
      await pumpWithLanguage(tester);
      expect(find.text('ابدأ'), findsOneWidget, reason: 'a stored choice applies from the first frame');

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      expect(settings.current.localeCode, 'en');
      expect(find.text('Begin'), findsOneWidget);
      expect(directionAt(tester, find.text('Begin')), TextDirection.ltr);
    });
  });

  testWidgets('swiping does not skip steps', (tester) async {
    await pumpPage(tester);
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(cubitOf(tester).state.step, OnboardingStep.welcome);
    expect(find.text('Begin'), findsOneWidget);
  });

  testWidgets('system back goes to the previous step; on step 1 it is not intercepted', (tester) async {
    await pumpPage(tester);
    await primary(tester);
    await primary(tester);
    expect(cubitOf(tester).state.step, OnboardingStep.workHours);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(cubitOf(tester).state.step, OnboardingStep.routines);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(cubitOf(tester).state.step, OnboardingStep.welcome);
    expect(find.text('Begin'), findsOneWidget);

    // Step 1: default behaviour (nothing to pop, the app would close).
    expect(await tester.binding.handlePopRoute(), isFalse);
    expect(cubitOf(tester).state.step, OnboardingStep.welcome);
  });

  testWidgets('routines step: defaults, interval choice, at-least-one rule', (tester) async {
    await pumpPage(tester);
    await primary(tester);
    expect(find.text('Your routines'), findsOneWidget);
    for (final t in RoutineType.values) {
      expect(tester.widget<Switch>(find.byKey(Key('routine-switch-${t.name}'))).value, isTrue);
    }
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('interval-hydration-45'))).selected, isTrue);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('interval-eyeRest-20'))).selected, isTrue);

    await tester.tap(find.byKey(const Key('interval-hydration-90')));
    await tester.pump();
    expect(cubitOf(tester).state.routine(RoutineType.hydration)!.intervalMinutes, 90);

    for (final t in RoutineType.values) {
      await tester.tap(find.byKey(Key('routine-switch-${t.name}')));
      await tester.pump();
    }
    expect(find.byKey(const Key('routines-hint')), findsOneWidget);
    expect(primaryEnabled(tester), isFalse);
    // Chips of an off routine are inert.
    await tester.tap(find.byKey(const Key('interval-stretch-30')), warnIfMissed: false);
    await tester.pump();
    expect(cubitOf(tester).state.routine(RoutineType.stretch)!.intervalMinutes, 60);

    await tester.tap(find.byKey(const Key('routine-switch-stretch')));
    await tester.pump();
    expect(find.byKey(const Key('routines-hint')), findsNothing);
    expect(primaryEnabled(tester), isTrue);
  });

  testWidgets('work hours step: summary, custom days, validation, back', (tester) async {
    await pumpPage(tester);
    await primary(tester);
    await primary(tester);
    expect(find.text('Your work hours'), findsOneWidget);
    expect(find.text('Sun–Thu · 09:00–17:00'), findsOneWidget);
    expect(find.byKey(const Key('day-7')), findsNothing);

    await tester.tap(find.byKey(const Key('preset-monFri')));
    await tester.pump();
    expect(find.text('Mon–Fri · 09:00–17:00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('preset-custom')));
    await tester.pump();
    expect(find.byKey(const Key('day-7')), findsOneWidget);
    expect(find.byKey(const Key('day-6')), findsOneWidget);
    await tester.tap(find.byKey(const Key('day-6')));
    await tester.pump();
    expect(find.text('Mon–Fri, Sat · 09:00–17:00'), findsNothing);
    expect(cubitOf(tester).state.days, {1, 2, 3, 4, 5, 6});

    for (final d in [1, 2, 3, 4, 5, 6]) {
      await tester.tap(find.byKey(Key('day-$d')));
      await tester.pump();
    }
    expect(find.text('Pick at least one work day.'), findsOneWidget);
    expect(primaryEnabled(tester), isFalse);

    await tester.tap(find.byKey(const Key('day-1')));
    await tester.pump();
    expect(primaryEnabled(tester), isTrue);

    cubitOf(tester).setEnd(9 * 60);
    await tester.pump();
    expect(find.text('End time must be after the start.'), findsOneWidget);
    expect(primaryEnabled(tester), isFalse);
    cubitOf(tester).setEnd(9 * 60 + 15);
    await tester.pump();
    expect(find.text('Work hours must be at least 30 minutes long.'), findsOneWidget);
    cubitOf(tester).setEnd(18 * 60);
    await tester.pump();
    expect(find.text('Mon · 09:00–18:00'), findsOneWidget);
    expect(find.text('Need split shifts? You can fine-tune later in Settings.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-back')));
    await tester.pumpAndSettle();
    expect(find.text('Your routines'), findsOneWidget);
  });

  testWidgets('the time picker updates the start time', (tester) async {
    await pumpPage(tester);
    await primary(tester);
    await primary(tester);
    await tester.tap(find.byKey(const Key('start-time')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(cubitOf(tester).state.startMinute, 9 * 60);
  });

  testWidgets('oath step: enable reminders, battery note (Android is the test default), finish saves everything', (
    tester,
  ) async {
    await pumpPage(tester);
    await primary(tester);
    await tester.tap(find.byKey(const Key('interval-hydration-30')));
    await primary(tester);
    await primary(tester);
    expect(find.text('Take the Oath'), findsWidgets);
    expect(find.byKey(const Key('battery-note')), findsOneWidget);
    expect(find.byKey(const Key('reminders-enabled')), findsNothing);

    await tester.tap(find.byKey(const Key('enable-reminders')));
    await tester.pumpAndSettle();
    expect(gateway.requestPermissionCalls, 1);
    expect(find.byKey(const Key('reminders-enabled')), findsOneWidget);
    reconciler.calls.clear(); // the permission grant reconciles on its own

    expect(settings.current.onboardingCompleted, isFalse);
    await tester.tap(find.byKey(const Key('onboarding-primary')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.current.onboardingCompleted, isTrue);
    expect((await routines.getAll()).first.intervalMinutes, 30);
    expect(reconciler.calls, [ReconcileTrigger.manual]);
  });

  testWidgets('finishing works without notification permission and hides the battery note off Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    gateway.grantOnRequest = false;
    await pumpPage(tester);
    await primary(tester);
    await primary(tester);
    await primary(tester);
    expect(find.byKey(const Key('battery-note')), findsNothing);
    await tester.tap(find.byKey(const Key('enable-reminders')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reminders-blocked')), findsOneWidget);

    expect(primaryEnabled(tester), isTrue);
    await tester.tap(find.byKey(const Key('onboarding-primary')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.current.onboardingCompleted, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a double tap on the oath button finishes once', (tester) async {
    reconciler.delay = const Duration(milliseconds: 50);
    await pumpPage(tester);
    await primary(tester);
    await primary(tester);
    await primary(tester);
    final button = find.byKey(const Key('onboarding-primary'));
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(reconciler.calls, [ReconcileTrigger.manual]);
  });

  group('launch at login', () {
    Future<void> toOath(WidgetTester tester) async {
      await pumpPage(tester);
      await primary(tester);
      await primary(tester);
      await primary(tester);
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('onboarding-primary')));
      await tester.pump(const Duration(milliseconds: 100));
    }

    for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
      testWidgets('$platform: the switch is on by default and finish enables it', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await toOath(tester);
          expect(find.text('Start Knight Rise when you sign in'), findsOneWidget);
          expect(tester.widget<SwitchListTile>(find.byKey(const Key('launch-at-login-switch'))).value, isTrue);
          await finish(tester);
          expect(launch.sets, [true]);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('turning it off applies false', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await toOath(tester);
        await tester.tap(find.byKey(const Key('launch-at-login-switch')));
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(find.byKey(const Key('launch-at-login-switch'))).value, isFalse);
        await finish(tester);
        expect(launch.sets, [false]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a registration failure still completes onboarding', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        launch.throwOnSet = StateError('boom');
        await toOath(tester);
        await finish(tester);
        expect(settings.current.onboardingCompleted, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('$platform: no switch and no registration', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await toOath(tester);
          expect(find.byKey(const Key('launch-at-login-switch')), findsNothing);
          await finish(tester);
          expect(launch.sets, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('Arabic copy, no overflow at 2x text on a narrow window (Oath step)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        tester.view
          ..physicalSize = const Size(400, 640)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final locale = LocaleCubit(settings);
        addTearDown(locale.close);
        await locale.load();
        await locale.setLocale(const Locale('ar'));
        final permission = NotificationPermissionCubit(gateway, reconciler);
        addTearDown(permission.close);
        await permission.check();
        await tester.pumpWidget(
          BlocProvider.value(value: permission, child: localizedApp(locale, const OnboardingPage())),
        );
        await tester.pumpAndSettle();
        await primary(tester);
        await primary(tester);
        await primary(tester);
        // Scaled on the Oath step; the sweep below covers every step at 2x.
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpAndSettle();
        expect(find.text('ابدأ Knight Rise عند تسجيل الدخول'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('no overflow on any step at 400x640 and 2x text', () {
    for (final code in const ['en', 'ar']) {
      testWidgets(code, (tester) async {
        tester.view
          ..physicalSize = const Size(400, 640)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final locale = LocaleCubit(settings);
        addTearDown(locale.close);
        await locale.load();
        await locale.setLocale(Locale(code));
        final permission = NotificationPermissionCubit(gateway, reconciler);
        addTearDown(permission.close);
        await permission.check();
        await tester.pumpWidget(
          BlocProvider.value(value: permission, child: localizedApp(locale, const OnboardingPage())),
        );
        await tester.pumpAndSettle();
        for (var step = 0; step < 4; step++) {
          expect(tester.takeException(), isNull, reason: 'step ${step + 1}');
          if (step < 3) {
            await tester.ensureVisible(find.byKey(const Key('onboarding-primary')));
            await primary(tester);
          }
        }
      });
    }
  });
}
