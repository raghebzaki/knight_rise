import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/services/schedule_reconciler.dart';

enum NotificationPermissionStatus {
  /// Not checked yet; the UI shows nothing.
  unknown,
  enabled,
  disabled,

  /// Disabled, and the user chose "Not now" in this app session.
  dismissed,
}

class NotificationPermissionState extends Equatable {
  const NotificationPermissionState(this.status, {this.requestDenied = false});

  final NotificationPermissionStatus status;

  /// The user tapped Enable and notifications are still off, so the system
  /// will not prompt again and only system settings can help.
  final bool requestDenied;

  bool get showPrompt => status == NotificationPermissionStatus.disabled;

  @override
  List<Object?> get props => [status, requestDenied];
}

/// Tracks whether notifications are allowed and drives the "Enable
/// reminders" card. Never prompts by itself: the system dialog only appears
/// from [request], i.e. after the user taps Enable (this avoids spending
/// Android 13's two-prompt limit on launch).
@injectable
class NotificationPermissionCubit extends Cubit<NotificationPermissionState> {
  NotificationPermissionCubit(this._gateway, this._reconciler)
    : super(const NotificationPermissionState(NotificationPermissionStatus.unknown));

  final NotificationGateway _gateway;
  final ScheduleReconciler _reconciler;
  bool _requesting = false;

  /// Reads the current permission. Call on start and on every app resume.
  Future<void> check() async {
    final enabled = await _gateway.notificationsEnabled();
    if (isClosed) return;
    if (enabled) {
      emit(const NotificationPermissionState(NotificationPermissionStatus.enabled));
    } else if (state.status != NotificationPermissionStatus.dismissed) {
      emit(NotificationPermissionState(NotificationPermissionStatus.disabled, requestDenied: state.requestDenied));
    }
  }

  /// Shows the system prompt, re-checks, and if notifications just became
  /// enabled arms the schedule (the launch reconcile planned them while they
  /// were blocked).
  Future<void> request() async {
    if (_requesting) return;
    _requesting = true;
    try {
      final wasEnabled = state.status == NotificationPermissionStatus.enabled;
      await _gateway.requestPermission();
      final enabled = await _gateway.notificationsEnabled();
      if (isClosed) return;
      if (enabled) {
        emit(const NotificationPermissionState(NotificationPermissionStatus.enabled));
        if (!wasEnabled) await _reconciler.reconcile(ReconcileTrigger.manual);
      } else {
        emit(const NotificationPermissionState(NotificationPermissionStatus.disabled, requestDenied: true));
      }
    } finally {
      _requesting = false;
    }
  }

  /// Hides the card until the app restarts.
  void dismiss() {
    if (state.status == NotificationPermissionStatus.disabled) {
      emit(NotificationPermissionState(NotificationPermissionStatus.dismissed, requestDenied: state.requestDenied));
    }
  }
}
