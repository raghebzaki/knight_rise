import 'dart:ui' show Locale;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/platform/device_locales.dart';
import 'package:knight_rise/features/notifications/data/desktop_toast_codec.dart';
import 'package:knight_rise/features/notifications/data/desktop_toasts.dart';
import 'package:knight_rise/features/notifications/data/notification_content.dart';
import 'package:knight_rise/features/notifications/data/toast_reminder_presenter.dart';
import 'package:knight_rise/features/notifications/domain/due_reminder.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes.dart';

class _MockToasts extends Mock implements DesktopToasts;

class _Device implements DeviceLocales {
  _Device(this.current);

  @override
  final List<Locale> current;
}

class _ThrowingSettings extends FakeSettingsRepository {
  @override
  Future<AppSettings> get() async => throw StateError('db closed');
}

void main() {
  late _MockToasts toasts;
  late FakeSettingsRepository settings;
  final fireAt = DateTime.utc(2026, 10, 9, 9);

  setUp(() {
    toasts = _MockToasts();
    settings = FakeSettingsRepository();
    when(
      () => toasts.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: any(named: 'payload'),
        doneLabel: any(named: 'doneLabel'),
        snoozeLabel: any(named: 'snoozeLabel'),
      ),
    ).thenAnswer((_) async {});
  });

  ToastReminderPresenter presenter([List<Locale> device = const []]) =>
      ToastReminderPresenter(toasts, settings, _Device(device));

  /// Arguments of every `show` call, flattened: id, title, body, payload, done, snooze.
  List<Object?> shown() => verify(
    () => toasts.show(
      id: captureAny(named: 'id'),
      title: captureAny(named: 'title'),
      body: captureAny(named: 'body'),
      payload: captureAny(named: 'payload'),
      doneLabel: captureAny(named: 'doneLabel'),
      snoozeLabel: captureAny(named: 'snoozeLabel'),
    ),
  ).captured;

  DueReminder due(Set<RoutineType> types, {bool recovery = false}) => DueReminder(
    id: 77,
    reminder: PlannedReminder(fireAt: fireAt, types: types, recovery: recovery),
  );

  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  test('English by default, with English button labels', () async {
    await presenter().present(due({RoutineType.hydration}));
    final args = shown();
    final copy = NotificationCopy.build({RoutineType.hydration}, l10n: en);
    expect(args.sublist(0, 3), [77, copy.title, copy.body]);
    expect(args[4], en.done);
    expect(args[5], en.snooze10);
  });

  test('stored Arabic wins over an English device', () async {
    await settings.save(settings.current.copyWith(localeCode: 'ar'));
    await presenter(const [Locale('en')]).present(due({RoutineType.stretch}));
    final args = shown();
    expect(args[1], NotificationCopy.build({RoutineType.stretch}, l10n: ar).title);
    expect(args[4], ar.done);
  });

  test('follow-device picks the Arabic device language', () async {
    await presenter(const [Locale('ar', 'EG')]).present(due({RoutineType.eyeRest}));
    expect(shown()[1], NotificationCopy.build({RoutineType.eyeRest}, l10n: ar).title);
  });

  test('unreadable settings fall back to the device language', () async {
    settings = _ThrowingSettings();
    await presenter(const [Locale('ar')]).present(due({RoutineType.eyeRest}));
    expect(shown()[4], ar.done);
  });

  test('a language switch applies to the very next toast', () async {
    final p = presenter();
    await p.present(due({RoutineType.hydration}));
    await settings.save(settings.current.copyWith(localeCode: 'ar'));
    await p.present(due({RoutineType.hydration}));
    final args = shown();
    expect(args[1], NotificationCopy.build({RoutineType.hydration}, l10n: en).title);
    expect(args[7], NotificationCopy.build({RoutineType.hydration}, l10n: ar).title);
  });

  test('merged and recovery copy', () async {
    await presenter().present(due({RoutineType.hydration, RoutineType.eyeRest}));
    var args = shown();
    var copy = NotificationCopy.build({RoutineType.hydration, RoutineType.eyeRest}, l10n: en);
    expect(args.sublist(1, 3), [copy.title, copy.body]);

    clearInteractions(toasts);
    await presenter().present(due({RoutineType.stretch}, recovery: true));
    args = shown();
    copy = NotificationCopy.build({RoutineType.stretch}, recovery: true, l10n: en);
    expect(args.sublist(1, 3), [copy.title, copy.body]);
  });

  test('the payload round-trips to the right action for a body click and each button', () async {
    await presenter().present(due({RoutineType.hydration, RoutineType.stretch}));
    final payload = shown()[3]! as String;
    final body = encodeToastArgument('', payload);
    final done = encodeToastArgument('done', payload);
    final snooze = encodeToastArgument('snooze', payload);
    // `show` receives the bare payload and wraps it itself; the codec accepts
    // both the wrapped (body) and the button argument forms.
    for (final (arg, kind) in [
      (body, ReminderActionKind.open),
      (done, ReminderActionKind.done),
      (snooze, ReminderActionKind.snooze),
    ]) {
      final action = reminderActionFromDesktopResponse(
        NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          id: 77,
          actionId: arg,
          payload: arg,
        ),
      );
      expect(action?.kind, kind);
      expect(action?.types, {RoutineType.hydration, RoutineType.stretch});
      expect(action?.scheduledAt, fireAt);
      expect(action?.notificationId, 77);
    }
  });
}
