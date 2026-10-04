import 'package:freezed_annotation/freezed_annotation.dart';

part 'reconcile_run.freezed.dart';

/// What woke the reconciler.
enum ReconcileTrigger { launch, resume, configChange, action, boot, periodic, timezoneChange }

/// One audit-log entry: a single reconcile pass and what it changed.
@freezed
abstract class ReconcileRun with _$ReconcileRun {
  const factory ReconcileRun({
    required DateTime at,
    required ReconcileTrigger trigger,
    required int planned,
    required int added,
    required int cancelled,
    String? error,
  }) = _ReconcileRun;
}
