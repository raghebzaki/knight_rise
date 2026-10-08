// dart format width=80
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/database/app_database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;

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

  test('migration from v3 to v4 keeps data, defaults the streak threshold, adds summary tables', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 3,
      newVersion: 4,
      createOld: v3.DatabaseAtV3.new,
      createNew: v4.DatabaseAtV4.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch
          ..insertAll(oldDb.routines, [
            const v3.RoutinesData(
              type: 'stretch',
              intervalMinutes: 50,
              dailyTarget: 7,
              enabled: 1,
              mode: 'fixedGrid',
            ),
          ])
          ..insertAll(oldDb.workWindows, [
            const v3.WorkWindowsData(
              id: 1,
              weekday: 2,
              startMinute: 480,
              endMinute: 960,
            ),
          ])
          ..insertAll(oldDb.reminderEvents, [
            const v3.ReminderEventsData(
              id: 1,
              routineType: 'hydration',
              outcome: 'done',
              at: 1759650000,
              waterMl: 500,
            ),
          ])
          ..insertAll(oldDb.appSettings, [
            const v3.AppSettingsData(
              id: 1,
              themeVariant: 'amoled',
              precisionTiming: 0,
              waterPerTapMl: 250,
              timezoneId: 'Asia/Dubai',
              onboardingCompleted: 1,
              shieldRecoverOnExit: 0,
            ),
          ])
          ..insertAll(oldDb.shieldSessions, [
            const v3.ShieldSessionsData(
              id: 1,
              startAt: 1759650000,
              endAt: 1759653000,
              endedAt: 1759651000,
              reason: 'meeting',
            ),
          ])
          ..insertAll(oldDb.dayOverrides, [
            const v3.DayOverridesData(
              date: '2026-10-05',
              kind: 'extend',
              extendMinutes: 60,
            ),
          ]);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.routines).get(), [
          const v4.RoutinesData(
            type: 'stretch',
            intervalMinutes: 50,
            dailyTarget: 7,
            enabled: 1,
            mode: 'fixedGrid',
          ),
        ]);
        expect(await newDb.select(newDb.workWindows).get(), [
          const v4.WorkWindowsData(
            id: 1,
            weekday: 2,
            startMinute: 480,
            endMinute: 960,
          ),
        ]);
        expect(await newDb.select(newDb.reminderEvents).get(), [
          const v4.ReminderEventsData(
            id: 1,
            routineType: 'hydration',
            outcome: 'done',
            at: 1759650000,
            waterMl: 500,
          ),
        ]);
        expect(await newDb.select(newDb.appSettings).get(), [
          const v4.AppSettingsData(
            id: 1,
            themeVariant: 'amoled',
            precisionTiming: 0,
            waterPerTapMl: 250,
            timezoneId: 'Asia/Dubai',
            onboardingCompleted: 1,
            shieldRecoverOnExit: 0,
            streakThresholdPercent: 70,
          ),
        ]);
        expect(await newDb.select(newDb.shieldSessions).get(), [
          const v4.ShieldSessionsData(
            id: 1,
            startAt: 1759650000,
            endAt: 1759653000,
            endedAt: 1759651000,
            reason: 'meeting',
          ),
        ]);
        expect(await newDb.select(newDb.dayOverrides).get(), [
          const v4.DayOverridesData(
            date: '2026-10-05',
            kind: 'extend',
            extendMinutes: 60,
          ),
        ]);
        expect(await newDb.select(newDb.dailySummaries).get(), isEmpty);
        expect(await newDb.select(newDb.dailyRoutineSummaries).get(), isEmpty);
      },
    );
  });

  test(
    'migration from v1 to v4 keeps data and ends on the v4 schema',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 1,
        newVersion: 4,
        createOld: v1.DatabaseAtV1.new,
        createNew: v4.DatabaseAtV4.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch
            ..insertAll(oldDb.routines, [
              const v1.RoutinesData(
                type: 'eyeRest',
                intervalMinutes: 20,
                dailyTarget: 12,
                enabled: 1,
                mode: 'rolling',
              ),
            ])
            ..insertAll(oldDb.appSettings, [
              const v1.AppSettingsData(
                id: 1,
                themeVariant: 'midnight',
                precisionTiming: 1,
                waterPerTapMl: 300,
              ),
            ]);
        },
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.routines).get(), [
            const v4.RoutinesData(
              type: 'eyeRest',
              intervalMinutes: 20,
              dailyTarget: 12,
              enabled: 1,
              mode: 'rolling',
            ),
          ]);
          expect(await newDb.select(newDb.appSettings).get(), [
            const v4.AppSettingsData(
              id: 1,
              themeVariant: 'midnight',
              precisionTiming: 1,
              waterPerTapMl: 300,
              onboardingCompleted: 1,
              shieldRecoverOnExit: 1,
              streakThresholdPercent: 70,
            ),
          ]);
          expect(await newDb.select(newDb.reconcileRuns).get(), isEmpty);
          expect(await newDb.select(newDb.shieldSessions).get(), isEmpty);
          expect(await newDb.select(newDb.dayOverrides).get(), isEmpty);
          expect(await newDb.select(newDb.dailySummaries).get(), isEmpty);
          expect(
            await newDb.select(newDb.dailyRoutineSummaries).get(),
            isEmpty,
          );
        },
      );
    },
  );

  test(
    'migration from v4 to v5 keeps settings and summaries, enables haptics',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 4,
        newVersion: 5,
        createOld: v4.DatabaseAtV4.new,
        createNew: v5.DatabaseAtV5.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch
            ..insertAll(oldDb.appSettings, [
              const v4.AppSettingsData(
                id: 1,
                themeVariant: 'amoled',
                precisionTiming: 1,
                waterPerTapMl: 250,
                timezoneId: 'Africa/Cairo',
                onboardingCompleted: 1,
                shieldRecoverOnExit: 1,
                streakThresholdPercent: 80,
                lastRetentionRunAt: 1760000000,
              ),
            ])
            ..insertAll(oldDb.dailySummaries, [
              const v4.DailySummariesData(
                date: '2026-10-12',
                isWorkDay: 1,
                waterMl: 1500,
                waterTargetMl: 2000,
                focusMinutes: 25,
                thresholdPercent: 80,
                qualified: 0,
                finalizedAt: 1760300000,
              ),
            ])
            ..insertAll(oldDb.dailyRoutineSummaries, [
              const v4.DailyRoutineSummariesData(
                date: '2026-10-12',
                routineType: 'stretch',
                done: 4,
                target: 6,
                enabled: 1,
              ),
            ]);
        },
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.appSettings).get(), [
            const v5.AppSettingsData(
              id: 1,
              themeVariant: 'amoled',
              precisionTiming: 1,
              waterPerTapMl: 250,
              timezoneId: 'Africa/Cairo',
              onboardingCompleted: 1,
              shieldRecoverOnExit: 1,
              streakThresholdPercent: 80,
              lastRetentionRunAt: 1760000000,
              hapticsEnabled: 1,
            ),
          ]);
          expect(await newDb.select(newDb.dailySummaries).get(), hasLength(1));
          expect(await newDb.select(newDb.dailyRoutineSummaries).get(), [
            const v5.DailyRoutineSummariesData(
              date: '2026-10-12',
              routineType: 'stretch',
              done: 4,
              target: 6,
              enabled: 1,
            ),
          ]);
        },
      );
    },
  );
}
