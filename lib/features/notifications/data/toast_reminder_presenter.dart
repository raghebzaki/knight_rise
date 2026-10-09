import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/core/platform/device_locales.dart';
import 'package:knight_rise/features/notifications/data/desktop_toasts.dart';
import 'package:knight_rise/features/notifications/data/notification_content.dart';
import 'package:knight_rise/features/notifications/data/notification_locale.dart';
import 'package:knight_rise/features/notifications/domain/due_reminder.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/notifications/domain/reminder_presenter.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Desktop: shows a due reminder as a toast. The copy is built here, at fire
/// time, in the language chosen right now, so a language switch applies to the
/// very next toast.
@desktopEnv
@LazySingleton(as: ReminderPresenter)
class ToastReminderPresenter implements ReminderPresenter {
  const ToastReminderPresenter(this._toasts, this._settings, this._deviceLocales);

  final DesktopToasts _toasts;
  final SettingsRepository _settings;
  final DeviceLocales _deviceLocales;

  @override
  Future<void> present(DueReminder due) async {
    String? code;
    try {
      code = (await _settings.get()).localeCode;
    } on Object catch (e) {
      debugPrint('Toast copy: settings unreadable, using the device language: $e');
    }
    final l = lookupAppLocalizations(resolveNotificationLocale(code, _deviceLocales.current));
    final content = NotificationCopy.build(due.reminder.types, recovery: due.reminder.recovery, l10n: l);
    await _toasts.show(
      id: due.id,
      title: content.title,
      body: content.body,
      payload: ReminderPayload.of(due.reminder).encode(),
      doneLabel: l.done,
      snoozeLabel: l.snooze10,
    );
  }
}
