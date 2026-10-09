import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/notifications/data/in_process_notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/due_reminder.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/reminder_presenter.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/desktop/desktop_alarm_clock.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';

class _RecordingPresenter implements ReminderPresenter {
  final List<DueReminder> shown = [];
  bool fail = false;

  @override
  Future<void> present(DueReminder due) async {
    shown.add(due);
    if (fail) throw StateError('toast failed');
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 9, 12);
  late InProcessNotificationGateway gateway;
  late _RecordingPresenter presenter;
  late DesktopAlarmClock alarm;

  PlannedReminder ago(Duration d, Set<RoutineType> types, {bool recovery = false}) =>
      PlannedReminder(fireAt: now.subtract(d), types: types, recovery: recovery);

  setUp(() {
    final clock = FixedClock(now);
    gateway = InProcessNotificationGateway(clock);
    presenter = _RecordingPresenter();
    alarm = DesktopAlarmClock(gateway, presenter, clock);
  });

  test('nothing due -> nothing presented, future entries stay pending', () async {
    final later = PlannedReminder(fireAt: now.add(const Duration(minutes: 5)), types: const {RoutineType.hydration});
    await gateway.schedule(later, exact: true);
    await alarm.tick();
    expect(presenter.shown, isEmpty);
    expect(await gateway.pendingIds(), {later.notificationId});
    expect(alarm.nextFireAt, later.fireAt);
  });

  test('one fresh reminder is presented as is', () async {
    final r = ago(const Duration(seconds: 30), {RoutineType.hydration});
    await gateway.schedule(r, exact: true);
    await alarm.tick();
    expect(presenter.shown, [DueReminder(id: r.notificationId, reminder: r)]);
    expect(await gateway.pendingIds(), isEmpty);
  });

  test('several fresh reminders collapse into one merged presentation', () async {
    final a = ago(const Duration(minutes: 5), {RoutineType.hydration}, recovery: true);
    final b = ago(const Duration(minutes: 1), {RoutineType.eyeRest}, recovery: true);
    await gateway.schedule(a, exact: true);
    await gateway.schedule(b, exact: true);
    await alarm.tick();
    final merged = PlannedReminder(
      fireAt: b.fireAt,
      types: const {RoutineType.hydration, RoutineType.eyeRest},
      recovery: true,
    );
    expect(presenter.shown, [DueReminder(id: merged.notificationId, reminder: merged)]);
  });

  test('merged reminder is recovery only if every member is', () async {
    await gateway.schedule(ago(const Duration(minutes: 5), {RoutineType.hydration}, recovery: true), exact: true);
    await gateway.schedule(ago(const Duration(minutes: 1), {RoutineType.stretch}), exact: true);
    await alarm.tick();
    expect(presenter.shown.single.reminder.recovery, isFalse);
  });

  test('stale reminders are dropped silently; the grace boundary is inclusive', () async {
    final stale = ago(DesktopAlarmClock.catchUpGrace + const Duration(seconds: 1), {RoutineType.hydration});
    final edge = ago(DesktopAlarmClock.catchUpGrace, {RoutineType.eyeRest});
    await gateway.schedule(stale, exact: true);
    await alarm.tick();
    expect(presenter.shown, isEmpty);
    expect(await gateway.pendingIds(), isEmpty);

    await gateway.schedule(edge, exact: true);
    await alarm.tick();
    expect(presenter.shown.single.reminder, edge);
  });

  test('mix of stale and fresh presents only the fresh one', () async {
    final stale = ago(const Duration(hours: 2), {RoutineType.hydration});
    final fresh = ago(const Duration(minutes: 2), {RoutineType.stretch});
    await gateway.schedule(stale, exact: true);
    await gateway.schedule(fresh, exact: true);
    await alarm.tick();
    expect(presenter.shown, [DueReminder(id: fresh.notificationId, reminder: fresh)]);
    expect(await gateway.pendingIds(), isEmpty);
  });

  test('the test notification is presented on its own', () async {
    final r = ago(const Duration(minutes: 1), {RoutineType.stretch});
    await gateway.schedule(r, exact: true);
    await gateway.scheduleTest(at: now.subtract(const Duration(seconds: 10)));
    await alarm.tick();
    expect(presenter.shown.map((d) => d.id), [kTestNotificationId, r.notificationId]);
  });

  test('presenter failure does not throw and due items are still removed', () async {
    presenter.fail = true;
    await gateway.schedule(ago(const Duration(minutes: 1), {RoutineType.hydration}), exact: true);
    await gateway.scheduleTest(at: now.subtract(const Duration(seconds: 10)));
    await expectLater(alarm.tick(), completes);
    expect(presenter.shown, hasLength(2));
    expect(await gateway.pendingIds(), isEmpty);
  });
}
