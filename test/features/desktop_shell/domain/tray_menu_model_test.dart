import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/features/desktop_shell/domain/tray_menu_model.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../helpers/tz.dart';

void main() {
  // DesktopShell loads these before building; the pure model expects them.
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  final cairoLoc = cairo;
  final now = DateTime.utc(2026, 10, 9, 9);
  // 14:30 UTC is 17:30 in Cairo (UTC+3 in October 2026).
  final next = DateTime.utc(2026, 10, 9, 14, 30);

  List<TrayMenuEntry> build({
    String locale = 'en',
    tz.Location? location,
    DateTime? nextReminderAt,
    DateTime? shieldUntil,
    LaunchAtLoginStatus launch = LaunchAtLoginStatus.disabled,
  }) => TrayMenuModel.build(
    l: lookupAppLocalizations(Locale(locale)),
    localeName: locale,
    location: location ?? cairoLoc,
    now: now,
    nextReminderAt: nextReminderAt,
    shieldUntil: shieldUntil,
    launchAtLogin: launch,
  );

  List<String> labels(List<TrayMenuEntry> e) => [
    for (final x in e)
      if (x.isSeparator) '---' else x.label,
  ];

  test('English, next reminder, in the zone not UTC', () {
    final menu = build(nextReminderAt: next);
    expect(labels(menu), [
      'Next reminder at 5:30\u202fPM',
      '---',
      'Open Knight Rise',
      'Focus 25 min',
      'Meeting 50 min',
      '---',
      'Launch at login',
      '---',
      'Quit Knight Rise',
    ]);
    expect(menu.first.enabled, isFalse);
    expect(menu.first.command, isNull);
    expect(
      [for (final e in menu) e.command],
      [
        null,
        null,
        TrayCommand.open,
        TrayCommand.shield25,
        TrayCommand.shield50,
        null,
        TrayCommand.toggleLaunchAtLogin,
        null,
        TrayCommand.quit,
      ],
    );
  });

  test('different zone gives a different time', () {
    expect(build(nextReminderAt: next, location: newYork).first.label, contains('10:30'));
  });

  test('no reminders scheduled', () {
    expect(build().first.label, 'No reminders scheduled');
  });

  test('shield active replaces the presets and the status line', () {
    final menu = build(nextReminderAt: next, shieldUntil: DateTime.utc(2026, 10, 9, 10));
    expect(menu.first.label, startsWith('Shield up until 1:00'));
    expect(labels(menu), contains('Lower Shield'));
    expect(labels(menu), isNot(contains('Focus 25 min')));
    expect(menu.firstWhere((e) => e.label == 'Lower Shield').command, TrayCommand.endShield);
  });

  test('an expired shield counts as none', () {
    final menu = build(shieldUntil: now.subtract(const Duration(minutes: 1)));
    expect(menu.first.label, 'No reminders scheduled');
  });

  test('Arabic labels', () {
    final menu = build(locale: 'ar', nextReminderAt: next);
    final l = labels(menu);
    expect(l[0], startsWith('التذكير التالي الساعة'));
    expect(l[2], 'فتح Knight Rise');
    expect(l[3], 'تركيز 25 دقيقة');
    expect(l[6], 'التشغيل عند تسجيل الدخول');
    expect(l[8], 'إنهاء Knight Rise');
    expect(build(locale: 'ar').first.label, 'لا توجد تذكيرات مجدولة');
    expect(
      build(locale: 'ar', shieldUntil: DateTime.utc(2026, 10, 9, 10)).map((e) => e.label),
      contains('إنهاء الدرع'),
    );
  });

  test('launch at login checkbox states', () {
    TrayMenuEntry entry(LaunchAtLoginStatus s) => build(launch: s).firstWhere((e) => e.label == 'Launch at login');
    expect(
      entry(LaunchAtLoginStatus.enabled),
      const TrayMenuEntry(label: 'Launch at login', command: TrayCommand.toggleLaunchAtLogin, checked: true),
    );
    expect(entry(LaunchAtLoginStatus.disabled).checked, isFalse);
    expect(entry(LaunchAtLoginStatus.disabled).enabled, isTrue);
    expect(entry(LaunchAtLoginStatus.requiresApproval).checked, isFalse);
    expect(entry(LaunchAtLoginStatus.requiresApproval).enabled, isTrue);
    expect(entry(LaunchAtLoginStatus.unavailable).checked, isFalse);
    expect(entry(LaunchAtLoginStatus.unavailable).enabled, isFalse);
  });

  test('managed by the system: a disabled text row without a checkbox or command', () {
    final menu = build(launch: LaunchAtLoginStatus.managedBySystem);
    expect(menu.where((e) => e.command == TrayCommand.toggleLaunchAtLogin), isEmpty);
    expect(
      menu.firstWhere((e) => e.label.startsWith('Launch at login')),
      const TrayMenuEntry(label: 'Launch at login (managed by Windows)', enabled: false),
    );
  });

  test('entries compare by value', () {
    expect(const TrayMenuEntry.separator(), const TrayMenuEntry.separator());
    expect(const TrayMenuEntry.separator().hashCode, const TrayMenuEntry.separator().hashCode);
    expect(const TrayMenuEntry(label: 'a'), isNot(const TrayMenuEntry(label: 'a', enabled: false)));
    expect(const TrayMenuEntry(label: ''), isNot(const TrayMenuEntry.separator()));
  });
}
