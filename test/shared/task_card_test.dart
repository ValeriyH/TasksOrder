import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/app_colors.dart';
import 'package:tasks_order/app/theme.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/task_card.dart';

import '../features/app_harness.dart';

void main() {
  final today = AppHarness.today;

  Future<void> pump(
    WidgetTester tester,
    Widget card, {
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('en'),
  }) => tester.pumpWidget(
    MaterialApp(
      theme: appTheme(brightness),
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ListView(children: [card])),
    ),
  );

  TaskCard card(
    Task task, {
    VoidCallback? onToggleDone,
    VoidCallback? onTap,
    bool isDone = false,
    bool paused = false,
    bool showFocus = true,
    bool showPinDate = true,
    List<Widget> chips = const [],
  }) => TaskCard(
    task: task,
    scale: 5,
    today: today,
    isDone: isDone,
    paused: paused,
    showFocus: showFocus,
    showPinDate: showPinDate,
    chips: chips,
    onToggleDone: onToggleDone ?? () {},
    onTap: onTap ?? () {},
  );

  /// The texts of the card's chips, in order.
  List<String> chipTexts(WidgetTester tester) => [
    for (final chip in [
      ...tester.widgetList(find.byType(PriorityChip)),
      ...tester.widgetList(find.byType(TaskChip)),
    ])
      switch (chip) {
        TaskChip(:final label) => label,
        _ => 'priority',
      },
  ];

  group('chips (D22)', () {
    testWidgets('an ordinary task shows its priority only', (tester) async {
      await pump(tester, card(testTask('a')));

      expect(find.text('Normal'), findsOneWidget);
      expect(chipTexts(tester), ['priority']);
      expect(find.text('No due date'), findsOneWidget);
    });

    testWidgets('focus, pin, repeat, list chips and paused in order', (
      tester,
    ) async {
      final task = testTask('a', isFocused: true, pinnedDate: today)
          .setRecurrence(
            Recurrence.interval(
              every: 1,
              unit: RecurrenceUnit.month,
              anchor: today,
            ),
            today: today,
            now: AppHarness.now,
          )
          .copyWith(notBefore: today.addDays(2));
      await pump(
        tester,
        card(task, paused: true, chips: const [TaskChip(label: 'list')]),
      );

      expect(chipTexts(tester), [
        'priority',
        'Focus',
        'Pinned to Fri, Nov 13',
        'Every month',
        'list',
        'Paused until tomorrow',
        // No "From": the pin leads (T-714).
      ]);
    });

    testWidgets('the pin chip without its date where the list says the day '
        '(T-911)', (tester) async {
      await pump(
        tester,
        card(testTask('a', pinnedDate: today.addDays(1)), showPinDate: false),
      );

      expect(chipTexts(tester), ['priority', 'Pinned']);
    });

    testWidgets('"Pinned to" its date in Ukrainian (T-911)', (tester) async {
      await pump(
        tester,
        card(testTask('a', pinnedDate: today.addDays(1))),
        locale: const Locale('uk'),
      );

      expect(find.textContaining('Закріплено на '), findsOneWidget);
    });

    testWidgets('"From" a later day when not pinned (T-714)', (tester) async {
      final task = testTask('a').copyWith(notBefore: today.addDays(2));
      await pump(tester, card(task));

      expect(chipTexts(tester), ['priority', 'From Sun, Nov 15']);
    });

    testWidgets('no focus chip where the screen says so (Today)', (
      tester,
    ) async {
      await pump(
        tester,
        card(testTask('a', isFocused: true), showFocus: false),
      );

      expect(find.text('Focus'), findsNothing);
    });

    testWidgets('a done task shows no "from" chip', (tester) async {
      await pump(
        tester,
        card(testTask('a').copyWith(notBefore: today.addDays(2)), isDone: true),
      );

      expect(find.textContaining('From'), findsNothing);
    });
  });

  group('due line', () {
    testWidgets('today, a later day, overdue in the alert colour', (
      tester,
    ) async {
      await pump(tester, card(testTask('a', dueDate: today)));
      expect(find.text('Due today'), findsOneWidget);

      await pump(tester, card(testTask('a', dueDate: today.addDays(3))));
      expect(find.text('Due Mon, Nov 16'), findsOneWidget);

      await pump(tester, card(testTask('a', dueDate: today.addDays(-2))));
      final overdue = tester.widget<Text>(find.text('Overdue by 2 days'));
      expect(overdue.style?.color, AppColors.light.alert);
    });

    testWidgets('in Ukrainian', (tester) async {
      await pump(tester, card(testTask('a')), locale: const Locale('uk'));

      expect(find.text('Без терміну'), findsOneWidget);
      expect(find.text('Готово'), findsOneWidget);
    });
  });

  group('Done button', () {
    testWidgets('"Done" calls back; a tap on the card calls its own', (
      tester,
    ) async {
      var toggled = 0;
      var tapped = 0;
      await pump(
        tester,
        card(
          testTask('a'),
          onToggleDone: () => toggled++,
          onTap: () => tapped++,
        ),
      );

      await tester.tap(find.text('Done'));
      expect((toggled, tapped), (1, 0));

      await tester.tap(find.text('Task a'));
      expect((toggled, tapped), (1, 1));
    });

    testWidgets('a done task: "Completed", dimmed, struck through', (
      tester,
    ) async {
      var toggled = 0;
      await pump(
        tester,
        card(testTask('a'), isDone: true, onToggleDone: () => toggled++),
      );

      expect(find.text('Completed'), findsOneWidget);
      final title = tester.widget<Text>(find.text('Task a'));
      expect(title.style?.decoration, TextDecoration.lineThrough);
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, AppDims.doneOpacity);

      await tester.tap(find.text('Completed'));
      expect(toggled, 1);
    });

    testWidgets('screen reader: a toggled button with the title', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, card(testTask('a')));
      expect(
        tester.getSemantics(find.byType(TaskDoneButton)),
        isSemantics(
          label: 'Mark as done: Task a',
          isButton: true,
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );

      await pump(tester, card(testTask('a'), isDone: true));
      expect(
        tester.getSemantics(find.byType(TaskDoneButton)),
        isSemantics(
          label: 'Mark as not done: Task a',
          isButton: true,
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('at least 44 high to tap', (tester) async {
      await pump(tester, card(testTask('a')));

      final size = tester.getSize(find.byType(TaskDoneButton));
      expect(size.height, greaterThanOrEqualTo(AppDims.minTapTarget));
    });

    testWidgets('paused: dimmed but still answers (with the hint)', (
      tester,
    ) async {
      var toggled = 0;
      await pump(
        tester,
        card(testTask('a'), paused: true, onToggleDone: () => toggled++),
      );

      final dimmed = tester.widget<Opacity>(
        find.ancestor(
          of: find.byType(TaskDoneButton),
          matching: find.byType(Opacity),
        ),
      );
      expect(dimmed.opacity, lessThan(1));
      await tester.tap(find.text('Done'));
      expect(toggled, 1);
    });
  });

  group('ghost', () {
    testWidgets('no Done button, the rule, a tap opens the task', (
      tester,
    ) async {
      var tapped = 0;
      final task = testTask('a').setRecurrence(
        Recurrence.weekdays(const {0, 2, 4}),
        today: today,
        now: AppHarness.now,
      );
      await pump(
        tester,
        GhostTaskCard(task: task, scale: 5, onTap: () => tapped++),
      );

      expect(find.byType(TaskDoneButton), findsNothing);
      expect(find.text('Mon, Wed, Fri'), findsOneWidget);
      await tester.tap(find.text('Task a'));
      expect(tapped, 1);
    });
  });

  testWidgets('dark theme: no shadow on the card', (tester) async {
    await pump(tester, card(testTask('a')), brightness: Brightness.dark);

    final shadows = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(TaskCard),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => (box.decoration as BoxDecoration).boxShadow)
        .whereType<List<BoxShadow>>();
    expect(shadows.expand((s) => s), isEmpty);
  });
}
