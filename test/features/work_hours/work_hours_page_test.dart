import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/presentation/work_hours_cubit.dart';
import 'package:knight_rise/features/work_hours/presentation/work_hours_page.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  late FakeWorkScheduleRepository repo;
  late WorkHoursCubit cubit;

  setUp(() async {
    repo = FakeWorkScheduleRepository();
    cubit = WorkHoursCubit(repo);
    await cubit.load();
  });

  tearDown(() => cubit.close());

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<TextButton>(find.byKey(const Key('saveButton'))).onPressed != null;

  testWidgets('shows seven days Sunday first with windows', (tester) async {
    await pumpPushed(tester, WorkHoursPage(cubit: cubit));
    final sunday = tester.getTopLeft(find.text('Sunday')).dy;
    final monday = tester.getTopLeft(find.text('Monday')).dy;
    final saturday = tester.getTopLeft(find.text('Saturday')).dy;
    expect(sunday, lessThan(monday));
    expect(monday, lessThan(saturday));
    expect(find.text('09:00 – 17:00'), findsNWidgets(5));
    expect(find.text('Day off'), findsNWidgets(2));
    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('an overlapping window shows an inline issue and disables Save', (tester) async {
    await pumpPushed(tester, WorkHoursPage(cubit: cubit));
    await tester.tap(find.byKey(const Key('addWindow1')));
    await tester.pump();
    expect(saveEnabled(tester), isTrue);

    cubit.updateWindow(DateTime.monday, 1, 16 * 60, 18 * 60);
    await tester.pumpAndSettle();
    expect(find.text('16:00 – 18:00: Windows overlap.'), findsOneWidget);
    expect(saveEnabled(tester), isFalse);

    cubit.updateWindow(DateTime.monday, 1, 17 * 60, 18 * 60);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('issue1')), findsNothing);
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('delete icon removes a window; day switch hides and restores it', (tester) async {
    await pumpPushed(tester, WorkHoursPage(cubit: cubit));
    await tester.tap(find.byKey(const Key('deleteWindow2-0')));
    await tester.pump();
    expect(find.text('No time windows'), findsOneWidget);

    await tester.tap(find.byKey(const Key('daySwitch1')));
    await tester.pump();
    expect(find.byKey(const Key('window1-0')), findsNothing);
    await tester.tap(find.byKey(const Key('daySwitch1')));
    await tester.pump();
    expect(find.byKey(const Key('window1-0')), findsOneWidget);
  });

  testWidgets('tapping a window runs the start and end pickers', (tester) async {
    await pumpPushed(tester, WorkHoursPage(cubit: cubit));
    await tester.tap(find.byKey(const Key('window7-0')));
    await tester.pumpAndSettle();
    expect(find.text('Start time'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('End time'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(cubit.state.windowsOf(DateTime.sunday), [TimeWindow.hm(9, 0, 17, 0)]);
  });

  testWidgets('Save writes the schedule and closes the page', (tester) async {
    await pumpPushed(tester, WorkHoursPage(cubit: cubit));
    await tester.tap(find.byKey(const Key('presetsMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mon–Fri 09–17'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();
    expect(repo.current.days.keys.toSet(), {1, 2, 3, 4, 5});
    expect(find.byType(WorkHoursPage), findsNothing);
  });

  testWidgets('back with unsaved changes asks first', (tester) async {
    await pumpPushed(tester, WorkHoursPage(cubit: cubit));
    cubit.setDayEnabled(DateTime.friday, enabled: true);
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkHoursPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkHoursPage), findsNothing);
    expect(repo.current, WorkSchedule.standard());
  });

  testWidgets('back without changes leaves immediately', (tester) async {
    await pumpPushed(tester, WorkHoursPage(cubit: cubit));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(WorkHoursPage), findsNothing);
  });
}
