/// Identifiers shared between Dart and the native projects for background work
/// and notifications. Changing a value here requires the matching native change
/// (Info.plist `BGTaskSchedulerPermittedIdentifiers`, AppDelegate.swift).
abstract final class BackgroundIds {
  /// iOS BGAppRefresh task identifier. Must equal the entry in Info.plist
  /// `BGTaskSchedulerPermittedIdentifiers` and the one registered in AppDelegate.swift.
  static const String iosReconcileTask = 'com.ragheb.knightRise.reconcile';

  /// Android WorkManager unique work name for the periodic reconcile job.
  static const String androidReconcileUniqueName = 'knight_rise_reconcile';

  /// Task name passed to the workmanager callback dispatcher for reconcile runs.
  static const String reconcileTaskName = 'com.ragheb.knightRise.reconcile';
}

/// Android notification channel ids (one per routine type plus a system channel).
abstract final class NotificationChannelIds {
  static const String hydration = 'hydration';
  static const String stretch = 'stretch';
  static const String eyeRest = 'eye_rest';

  /// Low-importance channel for status messages (e.g. Shield / paused notices).
  static const String system = 'system';
}

/// Notification action identifiers and the iOS category id.
abstract final class NotificationActionIds {
  /// iOS `DarwinNotificationCategory` id attached to every reminder.
  static const String iosCategory = 'knight_reminder';

  /// Action: mark the reminder done.
  static const String done = 'done';

  /// Action: snooze the reminder.
  static const String snooze = 'snooze';
}

/// Android drawable resource name (without extension) used as the notification
/// small icon: `android/app/src/main/res/drawable/ic_stat_knight.xml`.
const String androidNotificationIcon = 'ic_stat_knight';
