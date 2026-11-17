import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/app_colors.dart';
import 'package:tasks_order/app/theme.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/plan_badges.dart';
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
    List<TaskChip> chips = const [],
    int scale = 5,
  }) => TaskCard(
    task: task,
    scale: scale,
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
      // No due date: no due line (T-1103).
      expect(find.byIcon(Icons.schedule), findsNothing);
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
        card(
          task,
          paused: true,
          chips: const [TaskChip(label: 'list', slot: ChipSlot.planned)],
        ),
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

    testWidgets('a size mark for small and large tasks only (D21)', (
      tester,
    ) async {
      await pump(tester, card(testTask('a').copyWith(weight: 1)));
      expect(chipTexts(tester), ['priority', 'Small']);

      await pump(tester, card(testTask('a').copyWith(weight: 4)));
      expect(chipTexts(tester), ['priority', 'Large']);

      await pump(tester, card(testTask('a')));
      expect(chipTexts(tester), ['priority']);
      expect(find.byKey(const ValueKey('sizeChip')), findsNothing);

      // An unknown weight shows its nearest size.
      await pump(tester, card(testTask('a').copyWith(weight: 3)));
      expect(chipTexts(tester), ['priority', 'Large']);

      await pump(
        tester,
        card(testTask('a').copyWith(weight: 1)),
        locale: const Locale('uk'),
      );
      expect(find.text('Маленька'), findsOneWidget);
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

      await pump(
        tester,
        card(testTask('a', dueDate: today.addDays(-2))),
        locale: const Locale('uk'),
      );
      expect(find.textContaining('Прострочено'), findsOneWidget);
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

  group('allowed days (D23)', () {
    testWidgets('a chip with the days in the order of the week', (
      tester,
    ) async {
      await pump(tester, card(testTask('a').copyWith(allowedWeekdays: {4, 3})));

      expect(find.text('Only Thu, Fri'), findsOneWidget);
      expect(find.byKey(const ValueKey('daysChip')), findsOneWidget);
      expect(chipTexts(tester), ['priority', 'Only Thu, Fri']);
    });

    testWidgets('after the repeat chip and the planned day (T-1103)', (
      tester,
    ) async {
      final task = testTask('a')
          .copyWith(allowedWeekdays: {5})
          .setRecurrence(
            Recurrence.interval(
              every: 1,
              unit: RecurrenceUnit.week,
              anchor: today,
            ),
            today: today,
            now: AppHarness.now,
          );
      await pump(
        tester,
        card(
          task,
          chips: const [TaskChip(label: 'list', slot: ChipSlot.planned)],
        ),
      );

      expect(chipTexts(tester), ['priority', 'Every week', 'list', 'Only Sat']);
    });

    testWidgets('no chip without the limit', (tester) async {
      await pump(tester, card(testTask('a')));

      expect(find.byKey(const ValueKey('daysChip')), findsNothing);
    });

    testWidgets('in Ukrainian', (tester) async {
      await pump(
        tester,
        card(testTask('a').copyWith(allowedWeekdays: {5})),
        locale: const Locale('uk'),
      );

      expect(find.text('Лише Сб'), findsOneWidget);
    });
  });

  group('card v2, the quiet card (T-1103)', () {
    /// The background of the chip whose shell has [key], or of the chip
    /// with the text [text].
    Color? chipBackground(WidgetTester tester, Finder chip) {
      final box = tester.widget<Container>(
        find.descendant(of: chip, matching: find.byType(Container)).first,
      );
      return (box.decoration as BoxDecoration?)?.color;
    }

    Finder priorityChip() => find.byKey(const ValueKey('priorityChip'));

    Color? dot(WidgetTester tester) =>
        (tester
                    .widget<Container>(
                      find.byKey(const ValueKey('priorityDot')),
                    )
                    .decoration
                as BoxDecoration?)
            ?.color;

    testWidgets('the title is above the chips', (tester) async {
      await pump(tester, card(testTask('a')));

      expect(
        tester.getTopLeft(find.text('Task a')).dy,
        lessThan(tester.getTopLeft(priorityChip()).dy),
      );
      final title = tester.widget<Text>(find.text('Task a'));
      expect(title.maxLines, 2);
      expect(title.style?.fontSize, 18);
    });

    testWidgets('the chips of the list take their places', (tester) async {
      final entryChips = [
        const TaskChip(label: 'Deadline', slot: ChipSlot.deadline),
        const TaskChip(label: 'Waits', slot: ChipSlot.waitsForRoom),
        const TaskChip(
          label: '+ Over plan',
          slot: ChipSlot.overPlan,
          tone: ChipTone.extra,
        ),
        const TaskChip(
          label: 'At risk',
          slot: ChipSlot.atRisk,
          tone: ChipTone.alert,
        ),
        const TaskChip(label: 'On Sat, Nov 14', slot: ChipSlot.planned),
      ];
      final task = testTask(
        'a',
        isFocused: true,
        pinnedDate: today.addDays(1),
      ).copyWith(weight: 4, allowedWeekdays: {5});
      await pump(tester, card(task, chips: entryChips));

      expect(chipTexts(tester), [
        'priority',
        'At risk',
        'Focus',
        'Pinned to Sat, Nov 14',
        '+ Over plan',
        'On Sat, Nov 14',
        'Large',
        'Only Sat',
        'Waits',
        'Deadline',
      ]);
    });

    testWidgets('many chips wrap onto more lines, none is left out', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final task = testTask(
        'a',
        isFocused: true,
        pinnedDate: today.addDays(1),
      ).copyWith(weight: 4, allowedWeekdays: {5});
      await pump(
        tester,
        card(
          task,
          chips: const [
            TaskChip(label: 'On Sat, Nov 14', slot: ChipSlot.planned),
          ],
        ),
      );

      expect(find.byType(TaskChip), findsNWidgets(5));
      final first = tester.getTopLeft(priorityChip()).dy;
      final last = tester.getTopLeft(find.byType(TaskChip).last).dy;
      expect(last, greaterThan(first));
      expect(tester.takeException(), isNull);
    });

    testWidgets('quiet chips: grey with the meta text', (tester) async {
      await pump(tester, card(testTask('a', isFocused: true)));

      expect(
        chipBackground(tester, find.byType(TaskChip)),
        AppColors.light.neutralChipBg,
      );
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.center_focus_strong_outlined),
      );
      expect(icon.color, AppColors.light.metaText);
      expect(icon.size, 13);
      final label = tester.widget<Text>(find.text('Focus'));
      expect(label.style?.color, AppColors.light.metaText);
      expect(label.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('"+ Over plan" in the extra colour, no icon', (tester) async {
      const entry = PlanEntry(
        taskId: 'a',
        reason: PlanReason.priority,
        overflow: true,
      );
      late List<TaskChip> chips;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              chips = planEntryChips(
                context,
                entry,
                showReasons: false,
                overPlan: true,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await pump(tester, card(testTask('a'), chips: chips));

      final label = tester.widget<Text>(find.text('+ Over plan'));
      expect(label.style?.color, AppColors.light.metaExtra);
      expect(
        find.descendant(of: find.byType(TaskChip), matching: find.byType(Icon)),
        findsNothing,
      );
    });

    testWidgets('a quiet priority: grey chip, a dot of its colour', (
      tester,
    ) async {
      await pump(tester, card(testTask('a', priority: 3)));

      expect(
        chipBackground(tester, priorityChip()),
        AppColors.light.neutralChipBg,
      );
      expect(dot(tester), Color(PriorityLabels.color(3, 5)));
      expect(
        tester.widget<Text>(find.text('High')).style?.color,
        AppColors.light.metaText,
      );
    });

    testWidgets('loud: Catastrophic and Critical keep their own colours', (
      tester,
    ) async {
      PriorityShade shade(int priority, int scale) => PriorityShade.of(
        Color(PriorityLabels.color(priority, scale)),
        Brightness.light,
        AppColors.light.card,
      );
      // (priority, scale, loud)
      const cases = [
        (1, 10, true),
        (2, 10, true),
        (3, 10, false),
        (2, 5, true),
        (3, 5, false),
        (2, 3, true),
        (5, 3, false),
      ];
      for (final (priority, scale, loud) in cases) {
        await pump(
          tester,
          card(testTask('a', priority: priority), scale: scale),
        );
        expect(
          chipBackground(tester, priorityChip()),
          loud
              ? shade(priority, scale).background
              : AppColors.light.neutralChipBg,
          reason: 'priority $priority of scale $scale',
        );
      }
      // Catastrophic and Critical of scale 10 are not the same colour.
      expect(shade(1, 10), isNot(shade(2, 10)));
    });

    testWidgets('a done task: every chip quiet, a grey dot', (tester) async {
      await pump(
        tester,
        card(
          testTask('a', priority: 2),
          isDone: true,
          chips: const [
            TaskChip(
              label: 'At risk',
              slot: ChipSlot.atRisk,
              tone: ChipTone.alert,
            ),
          ],
        ),
      );

      expect(
        chipBackground(tester, priorityChip()),
        AppColors.light.neutralChipBg,
      );
      expect(dot(tester), AppColors.light.priorityDotDone);
      expect(
        chipBackground(tester, find.byType(TaskChip)),
        AppColors.light.neutralChipBg,
      );
    });

    testWidgets('"At risk" stays loud', (tester) async {
      await pump(
        tester,
        card(
          testTask('a'),
          chips: const [
            TaskChip(
              label: 'At risk',
              slot: ChipSlot.atRisk,
              tone: ChipTone.alert,
            ),
          ],
        ),
      );

      expect(
        chipBackground(tester, find.byType(TaskChip)),
        AppColors.light.capOverBg,
      );
    });

    testWidgets('without a due date the button stands at the right', (
      tester,
    ) async {
      await pump(tester, card(testTask('a')));
      final button = tester.getTopRight(find.byType(TaskDoneButton)).dx;
      final shell = tester.getTopRight(find.byType(TaskCard)).dx;

      // The card's right margin (16) and padding (14).
      expect(shell - button, lessThanOrEqualTo(30 + 1));
    });

    testWidgets('dark theme: the dot is the light shade of the level', (
      tester,
    ) async {
      await pump(
        tester,
        card(testTask('a', priority: 3)),
        brightness: Brightness.dark,
      );

      final shade = PriorityShade.of(
        Color(PriorityLabels.color(3, 5)),
        Brightness.dark,
        AppColors.dark.card,
      );
      expect(dot(tester), shade.foreground);
      expect(
        chipBackground(tester, priorityChip()),
        AppColors.dark.neutralChipBg,
      );
    });

    testWidgets('a ghost: the title first too', (tester) async {
      final task = testTask('a').setRecurrence(
        Recurrence.weekdays(const {0, 2, 4}),
        today: today,
        now: AppHarness.now,
      );
      await pump(tester, GhostTaskCard(task: task, scale: 5, onTap: () {}));

      expect(
        tester.getTopLeft(find.text('Task a')).dy,
        lessThan(tester.getTopLeft(priorityChip()).dy),
      );
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
