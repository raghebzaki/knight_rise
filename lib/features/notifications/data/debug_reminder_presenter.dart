import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/features/notifications/domain/due_reminder.dart';
import 'package:knight_rise/features/notifications/domain/reminder_presenter.dart';

/// Desktop placeholder: logs the due reminder instead of showing a toast.
@desktopEnv
@LazySingleton(as: ReminderPresenter)
class DebugReminderPresenter implements ReminderPresenter {
  const DebugReminderPresenter();

  @override
  Future<void> present(DueReminder due) async => debugPrint('[reminder] due: ${due.reminder} (id ${due.id})');
}
