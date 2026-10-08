// dart format width=80
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/database/app_database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  test('migration from v1 to v2 keeps routines/settings data and adds timezone + reconcile_runs', () async {
    final oldRoutinesData = <v1.RoutinesData>[
      const v1.RoutinesData(
        type: 'hydration',
        intervalMinutes: 30,
        dailyTarget: 8,
        enabled: 1,
        mode: 'fixedGrid',
      ),
      const v1.RoutinesData(
        type: 'stretch',
        intervalMinutes: 60,
        dailyTarget: 6,
        enabled: 0,
        mode: 'rolling',
      ),
    ];
    final expectedNewRoutinesData = <v2.RoutinesData>[
      const v2.RoutinesData(
        type: 'hydration',
        intervalMinutes: 30,
        dailyTarget: 8,
        enabled: 1,
        mode: 'fixedGrid',
      ),
      const v2.RoutinesData(
        type: 'stretch',
        intervalMinutes: 60,
        dailyTarget: 6,
        enabled: 0,
        mode: 'rolling',
      ),
    ];

    final oldWorkWindowsData = <v1.WorkWindowsData>[
      const v1.WorkWindowsData(
        id: 1,
        weekday: 7,
        startMinute: 540,
        endMinute: 1020,
      ),
    ];
    final expectedNewWorkWindowsData = <v2.WorkWindowsData>[
      const v2.WorkWindowsData(
        id: 1,
        weekday: 7,
        startMinute: 540,
        endMinute: 1020,
      ),
    ];

    final oldReminderEventsData = <v1.ReminderEventsData>[];
    final expectedNewReminderEventsData = <v2.ReminderEventsData>[];

    final oldAppSettingsData = <v1.AppSettingsData>[
      const v1.AppSettingsData(
        id: 1,
        themeVariant: 'amoled',
        precisionTiming: 1,
        waterPerTapMl: 500,
      ),
    ];
    final expectedNewAppSettingsData = <v2.AppSettingsData>[
      const v2.AppSettingsData(
        id: 1,
        themeVariant: 'amoled',
        precisionTiming: 1,
        waterPerTapMl: 500,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch
          ..insertAll(oldDb.routines, oldRoutinesData)
          ..insertAll(oldDb.workWindows, oldWorkWindowsData)
          ..insertAll(oldDb.reminderEvents, oldReminderEventsData)
          ..insertAll(oldDb.appSettings, oldAppSettingsData);
      },
      validateItems: (newDb) async {
        expect(
          await newDb.select(newDb.routines).get(),
          expectedNewRoutinesData,
        );
        expect(
          await newDb.select(newDb.workWindows).get(),
          expectedNewWorkWindowsData,
        );
        expect(
          await newDb.select(newDb.reminderEvents).get(),
          expectedNewReminderEventsData,
        );
        expect(
          await newDb.select(newDb.appSettings).get(),
          expectedNewAppSettingsData,
        );
        expect(await newDb.select(newDb.reconcileRuns).get(), isEmpty);
      },
    );
  });
  test('migration from v2 to v3 keeps data, marks onboarding done, adds shield + override tables', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 2,
      newVersion: 3,
      createOld: v2.DatabaseAtV2.new,
      createNew: v3.DatabaseAtV3.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch
          ..insertAll(oldDb.routines, [
            const v2.RoutinesData(
              type: 'eyeRest',
              intervalMinutes: 25,
              dailyTarget: 10,
              enabled: 1,
              mode: 'rolling',
            ),
          ])
          ..insertAll(oldDb.workWindows, [
            const v2.WorkWindowsData(
              id: 1,
              weekday: 1,
              startMinute: 600,
              endMinute: 900,
            ),
          ])
          ..insertAll(oldDb.appSettings, [
            const v2.AppSettingsData(
              id: 1,
              themeVariant: 'amoled',
              precisionTiming: 1,
              waterPerTapMl: 300,
              timezoneId: 'Africa/Cairo',
            ),
          ])
          ..insertAll(oldDb.reconcileRuns, [
            const v2.ReconcileRunsData(
              id: 1,
              at: 1000,
              trigger: 'launch',
              planned: 3,
              added: 3,
              cancelled: 0,
            ),
          ]);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.routines).get(), [
          const v3.RoutinesData(
            type: 'eyeRest',
            intervalMinutes: 25,
            dailyTarget: 10,
            enabled: 1,
            mode: 'rolling',
          ),
        ]);
        expect(await newDb.select(newDb.workWindows).get(), [
          const v3.WorkWindowsData(
            id: 1,
            weekday: 1,
            startMinute: 600,
            endMinute: 900,
          ),
        ]);
        expect(await newDb.select(newDb.appSettings).get(), [
          const v3.AppSettingsData(
            id: 1,
            themeVariant: 'amoled',
            precisionTiming: 1,
            waterPerTapMl: 300,
            timezoneId: 'Africa/Cairo',
            onboardingCompleted: 1,
            shieldRecoverOnExit: 1,
          ),
        ]);
        expect(await newDb.select(newDb.reconcileRuns).get(), [
          const v3.ReconcileRunsData(
            id: 1,
            at: 1000,
            trigger: 'launch',
            planned: 3,
            added: 3,
            cancelled: 0,
          ),
        ]);
        expect(await newDb.select(newDb.shieldSessions).get(), isEmpty);
        expect(await newDb.select(newDb.dayOverrides).get(), isEmpty);
      },
    );
  });

  test(
    'migration from v1 to v3 keeps data and ends on the v3 schema',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 1,
        newVersion: 3,
        createOld: v1.DatabaseAtV1.new,
        createNew: v3.DatabaseAtV3.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch
            ..insertAll(oldDb.routines, [
              const v1.RoutinesData(
                type: 'hydration',
                intervalMinutes: 30,
                dailyTarget: 8,
                enabled: 1,
                mode: 'fixedGrid',
              ),
            ])
            ..insertAll(oldDb.workWindows, [
              const v1.WorkWindowsData(
                id: 1,
                weekday: 7,
                startMinute: 540,
                endMinute: 1020,
              ),
            ])
            ..insertAll(oldDb.appSettings, [
              const v1.AppSettingsData(
                id: 1,
                themeVariant: 'midnight',
                precisionTiming: 0,
                waterPerTapMl: 500,
              ),
            ]);
        },
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.routines).get(), [
            const v3.RoutinesData(
              type: 'hydration',
              intervalMinutes: 30,
              dailyTarget: 8,
              enabled: 1,
              mode: 'fixedGrid',
            ),
          ]);
          expect(await newDb.select(newDb.workWindows).get(), [
            const v3.WorkWindowsData(
              id: 1,
              weekday: 7,
              startMinute: 540,
              endMinute: 1020,
            ),
          ]);
          expect(await newDb.select(newDb.appSettings).get(), [
            const v3.AppSettingsData(
              id: 1,
              themeVariant: 'midnight',
              precisionTiming: 0,
              waterPerTapMl: 500,
              onboardingCompleted: 1,
              shieldRecoverOnExit: 1,
            ),
          ]);
          expect(await newDb.select(newDb.reconcileRuns).get(), isEmpty);
          expect(await newDb.select(newDb.shieldSessions).get(), isEmpty);
          expect(await newDb.select(newDb.dayOverrides).get(), isEmpty);
        },
      );
    },
  );
}
