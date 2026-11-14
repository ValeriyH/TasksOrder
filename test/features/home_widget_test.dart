import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/domain/model/settings.dart';

import 'app_harness.dart';

/// The home-screen widget cache (T-601). The harness day is Friday
/// 13 November, 10:00, with Friday capacity 1, Saturday 3 and Sunday a rest
/// day.
void main() {
  final tasks = [
    for (final (i, id) in 'abcd'.split('').indexed) testTask(id, minute: i),
  ];

  Map<String, dynamic> last(AppHarness app) =>
      jsonDecode(app.homeWidget.payloads.last) as Map<String, dynamic>;

  List<Map<String, dynamic>> days(AppHarness app) => [
    for (final day in last(app)['days'] as List<dynamic>)
      day as Map<String, dynamic>,
  ];

  testWidgets('the app sends the coming week when it starts', (tester) async {
    final app = await AppHarness.start(tester, tasks: tasks);

    final payload = last(app);
    expect(payload['format'], 1);
    expect(payload['dayStartHour'], 0);
    expect(payload['stale'], 'Open TasksOrder to update the plan');
    final week = days(app);
    expect(week, hasLength(7));
    expect(week[0], {
      'date': '2026-11-13',
      'header': 'Today · 1/1',
      'lines': ['Task a'],
      'empty': null,
    });
    expect(week[1]['lines'], ['Task b', 'Task c', 'Task d']);
    expect(week[2], {
      'date': '2026-11-15',
      'header': 'Today',
      'lines': <String>[],
      'empty': 'Rest day',
    });
  });

  testWidgets('a completion updates the widget', (tester) async {
    final app = await AppHarness.start(tester, tasks: tasks);
    final sent = app.homeWidget.payloads.length;

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(app.homeWidget.payloads.length, greaterThan(sent));
    expect(days(app)[0], {
      'date': '2026-11-13',
      'header': 'Today · 0/1',
      'lines': <String>[],
      'empty': 'All done for today',
    });
  });

  testWidgets('an unchanged plan is not sent again', (tester) async {
    final app = await AppHarness.start(tester, tasks: tasks);
    final sent = app.homeWidget.payloads.length;

    // Switching tabs changes nothing in the plan.
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();

    expect(app.homeWidget.payloads.length, sent);
  });

  testWidgets('a long day ends in "+N more"', (tester) async {
    final app = await AppHarness.start(
      tester,
      tasks: [for (var i = 0; i < 12; i++) testTask('t$i', minute: i)],
      settings: Settings(weeklyCapacity: const [12, 12, 12, 12, 12, 12, 12]),
    );

    final lines = days(app)[0]['lines'] as List<dynamic>;
    expect(lines, hasLength(8));
    expect(lines.first, 'Task t0');
    expect(lines.last, '+5 more');
  });

  testWidgets('the texts follow the language of the app', (tester) async {
    final app = await AppHarness.start(
      tester,
      tasks: tasks,
      stored: {'device.locale': 'uk'},
    );

    expect(days(app)[0]['header'], 'Сьогодні · 1/1');
    expect(days(app)[2]['empty'], 'Вихідний');
    expect(last(app)['stale'], 'Відкрийте TasksOrder, щоб оновити план');
  });
}
