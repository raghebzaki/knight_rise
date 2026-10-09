import 'dart:io';
import 'dart:ui' show Locale;

import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/features/settings/data/drift_settings_repository.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/features/settings/presentation/locale_cubit.dart';
import 'package:knight_rise/l10n/app_locales.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';

void main() {
  group('LocaleCubit', () {
    late FakeSettingsRepository settings;

    setUp(() => settings = FakeSettingsRepository());

    test('starts on null: follow the device language', () async {
      final cubit = LocaleCubit(settings);
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state, isNull);
    });

    blocTest<LocaleCubit, Locale?>(
      'load emits the stored choice',
      setUp: () => settings.save(const AppSettings(localeCode: 'ar')),
      build: () => LocaleCubit(settings),
      act: (c) => c.load(),
      expect: () => [const Locale('ar')],
    );

    blocTest<LocaleCubit, Locale?>(
      'setLocale switches at once and persists the code, keeping other settings',
      setUp: () => settings.save(settings.current.copyWith(themeVariant: ThemeVariant.amoled, waterPerTapMl: 300)),
      build: () => LocaleCubit(settings),
      act: (c) async {
        await c.load();
        await c.setLocale(const Locale('ar'));
        await c.setLocale(const Locale('en'));
      },
      // null: the loaded "follow the device" state.
      expect: () => [null, const Locale('ar'), const Locale('en')],
      verify: (_) {
        expect(settings.current.localeCode, 'en');
        expect(settings.current.themeVariant, ThemeVariant.amoled);
        expect(settings.current.waterPerTapMl, 300);
      },
    );

    blocTest<LocaleCubit, Locale?>(
      'a region variant maps to the supported language; unsupported languages are ignored',
      build: () => LocaleCubit(settings),
      act: (c) async {
        await c.load();
        await c.setLocale(const Locale('ar', 'EG'));
        await c.setLocale(const Locale('fr'));
      },
      expect: () => [null, const Locale('ar')],
      verify: (_) => expect(settings.current.localeCode, 'ar'),
    );

    test('rapid switches end on, and persist, the last choice', () async {
      final cubit = LocaleCubit(settings);
      addTearDown(cubit.close);
      await cubit.load();
      final states = <Locale?>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);
      await Future.wait([cubit.setLocale(const Locale('ar')), cubit.setLocale(const Locale('en'))]);
      await Future<void>.delayed(Duration.zero);
      expect(states, [const Locale('ar'), const Locale('en')], reason: 'no flip back to an earlier choice');
      expect(settings.current.localeCode, 'en');
    });

    test('an unknown stored code falls back to the device language', () async {
      await settings.save(settings.current.copyWith(localeCode: 'xx'));
      final cubit = LocaleCubit(settings);
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state, isNull);
    });
  });

  group('persistence across app restarts (Drift on disk)', () {
    late Directory dir;

    setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
    setUp(() => dir = Directory.systemTemp.createTempSync('knight_locale_'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// One app run: open the database file, load the cubit, run [body], close.
    Future<void> run(Future<void> Function(LocaleCubit cubit) body) async {
      final db = AppDatabase(NativeDatabase(File('${dir.path}/knight_rise.sqlite')));
      final cubit = LocaleCubit(DriftSettingsRepository(db));
      await cubit.load();
      await body(cubit);
      await cubit.close();
      await db.close();
    }

    test('a fresh install follows the device language', () async {
      await run((cubit) async => expect(cubit.state, isNull));
    });

    test('the chosen language survives a restart, and so does switching back', () async {
      await run((cubit) => cubit.setLocale(const Locale('ar')));
      await run((cubit) async {
        expect(cubit.state, const Locale('ar'));
        await cubit.setLocale(const Locale('en'));
      });
      await run((cubit) async => expect(cubit.state, const Locale('en')));
    });
  });

  group('supported locales', () {
    test('English and Arabic, English first so it is the fallback', () {
      expect(kSupportedLocales, [const Locale('en'), const Locale('ar')]);
      expect(kSupportedLocales.toSet(), AppLocalizations.supportedLocales.toSet());
    });

    test('localeFromCode', () {
      expect(localeFromCode('ar'), const Locale('ar'));
      expect(localeFromCode('en'), const Locale('en'));
      expect(localeFromCode(null), isNull);
      expect(localeFromCode('fr'), isNull);
    });
  });
}
