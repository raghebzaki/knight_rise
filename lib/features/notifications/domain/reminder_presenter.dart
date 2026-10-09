import 'package:knight_rise/features/notifications/domain/due_reminder.dart';

/// Shows a due reminder (desktop toast).
abstract interface class ReminderPresenter {
  Future<void> present(DueReminder due);
}
