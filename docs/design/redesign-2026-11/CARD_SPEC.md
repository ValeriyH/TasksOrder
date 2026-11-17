# TasksOrder: картка задачі v2 («тиха картка»)

Доповнення до пакета `tasksorder-redesign` (`SPEC.md`, `tasks_order_design_tokens.dart`, `tasks_order_widgets_reference.dart`).
Цей документ **замінює** розділ «TaskCard» у `SPEC.md`. Усе інше в `SPEC.md` лишається чинним.

- Полотно: https://claude.ai/artifact/GCRk5PKnYE2U2phvtk2Y3p, ряд «Сьогодні · назва зверху і тиха картка», артборди «Тиха картка · світла / темна».
- Макет-джерело: `project/Today.dc.html` з параметром `cardLayout = "quiet"`.

Нова картка використовується на **всіх трьох екранах**: «Сьогодні», «План», «Завдання».

## Що змінено порівняно з попередньою серією (SPEC v1)

| # | Було (v1) | Стало (v2) |
|---|---|---|
| 1 | Зверху рядок чипів, під ним назва | **Назва зверху**, під нею рядок чипів |
| 2 | Назва 17 / w700, line-height 23 | Назва **18 / w700, line-height 24** |
| 3 | Відступ назва ↔ чипи = 10 (загальний gap картки) | Назва й чипи — окрема група з **gap 10**; від групи до нижнього рядка теж 10 |
| 4 | Чип пріоритету: кольоровий фон + кольоровий текст + кольорова крапка | **Нейтральний** чип: фон `neutralChipBg`, текст `metaText`, кольорова **лише крапка** (`priorityDot`) |
| 5 | — | **Виняток: «Критичний»,  «Під загрозою»** лишається кольоровим: фон і текст `priorities[critical]`, як у v1 |
| 6 | «Фокус» і «Закріплено»: акцентний фон `accentChipBg` / `accentChipFg` | **Нейтральні**: фон `neutralChipBg`, текст і іконка `metaText` |
| 7 | Повтор, «Заплановано на…»: текст `neutralChipFg` (яскравіший) | Текст **`metaText`** (приглушений) |
| 8 | «Понад план»: бурштиновий фон + іконка «+» | Текст **«+ Понад план»** без іконки, колір **`metaExtra`**, фон нейтральний `neutralChipBg` |
| 9 | Текст чипа 12 / w700 | Текст чипа **12 / w600** |
| 10 | «Заплановано на пн, 16 лист.» | Скорочено: **«На пн, 16 лист.»** (і «На сьогодні») |
| 11 | Рядок терміну показувався завжди («Без терміну», якщо дедлайну немає) | Рядок терміну **лише коли є дедлайн**. Без дедлайну в нижньому рядку тільки кнопка, притиснута **вправо** |
| 12 | — | Чипи **завжди показуються всі**, без «+N» і без обрізання. Переносяться на новий рядок (`Wrap`) |
| 13 | Порядок: пріоритет, фокус, закріплено, повтор, план, понад план | Порядок: **пріоритет, фокус, закріплено, понад план, повтор, план** (важливе — першим) |
| 14 | Виконана задача: чип пріоритету лишався кольоровим | Виконана задача: чип пріоритету **нейтральний** (і для «Критичний»), крапка сіра (`priorityDotDone`) |

Без змін: контейнер картки (radius 18, padding `fromLTRB(16, 14, 14, 12)`, фон, тінь), кнопка «Готово» / «Виконано», стан «виконано» (opacity 0.62, перекреслена назва, переміщення вниз групи), правила, які чипи показуються на якому екрані.

## Анатомія

```
┌──────────────────────────────────────────────┐
│ Оплатити комунальні послуги                  │  назва, 18/w700, макс. 2 рядки
│                                              │  ↕ 10
│ (● Високий) (📌 Закріплено) (+ Понад план)   │  чипи, Wrap, spacing 6, runSpacing 6
│ (↻ Щомісяця)                                 │
│                                              │  ↕ 10
│ 🕑 Прострочено на 2 дні           [✓ Готово]  │  термін (опційно) + кнопка
└──────────────────────────────────────────────┘
```

Без дедлайну:

```
│ Вивчити анімації у Flutter                   │
│ (● Звичайний) (📅 На вт, 17 лист.)            │
│                                   [✓ Готово]  │
```

## Назва

- 18 / w700, height 24/18, колір `title`.
- `maxLines: 2`, `overflow: ellipsis`.
- Виконано: колір `titleDone` + `TextDecoration.lineThrough`.

## Чипи

Спільне для всіх: висота 24, radius 12, горизонтальний padding 10, текст 12 / w600, іконка 13, відступ іконка ↔ текст 5 (у пріоритету крапка ↔ текст 6).

| Чип | Коли показується | Фон | Текст / іконка | Вміст |
|---|---|---|---|---|
| Пріоритет | завжди | `neutralChipBg` | `metaText` | крапка 8×8 кольору `priorityDot[p]` + мітка |
| Пріоритет «Критичний» (не виконано) | `priority == critical && !isDone` | `priorities[critical].background` | `priorities[critical].foreground` | крапка `priorityDot[critical]` + «Критичний» |
| Понад план | задача понад місткість дня | `neutralChipBg` | `metaExtra` | «+ Понад план», без іконки |
| Фокус | `focusedAt != null`, **крім «Сьогодні»** (там є секція «Фокус») | `neutralChipBg` | `metaText` | `center_focus_strong_outlined` + «Фокус» |
| Закріплено | `pinnedDate != null` | `neutralChipBg` | `metaText` | `push_pin_outlined` + «Закріплено» |
| Повтор | `recurrence != null` | `neutralChipBg` | `metaText` | `repeat` + текст правила («Щомісяця», «Пн, Ср, Пт») |
| План | «Завдання»: завжди; «Сьогодні»: лише фокус-задачі, заплановані не на сьогодні | `neutralChipBg` | `metaText` | `calendar_today_outlined` + «На пн, 16 лист.» / «На сьогодні» / «Пізніше» |

Виконана задача: усі чипи нейтральні, крапка пріоритету `priorityDotDone`.

## Нижній рядок

- `Row`: з терміном — [іконка + термін у `Expanded`] [12] [кнопка]; без терміну — `Spacer()` [кнопка].
- **Термін** показується лише для справжнього дедлайну: «Сьогодні до 18:00», «До пт, 20 лист.», «Прострочено на 2 дні». «Без терміну» **не показувати**. Дата плану — це не термін: вона живе в чипі.
- Стиль терміну: іконка `schedule` 14 + текст 13 / w600, колір `muted`. Прострочено (і не виконано): колір `alert`.
- Кнопка «Готово» / «Виконано» без змін (див. `SPEC.md`).

## Нові токени

Додай у `TasksOrderColors` (решта токенів без змін; `accentChipBg/Fg` і `extraChipBg/Fg` у картці більше не використовуються, але можуть лишитися для інших місць):

| Токен | Світла | Темна |
|---|---|---|
| `metaText` | #5F6673 | #9CA3AF |
| `metaExtra` | #92400E | #E3BC4E |
| `priorityDot.critical` | #DC2626 | #F87171 |
| `priorityDot.high` | #EA580C | #FB923C |
| `priorityDot.normal` | #16A34A | #4ADE80 |
| `priorityDot.low` | #2563EB | #60A5FA |
| `priorityDot.someday` | #9CA3AF | #6B7280 |
| `priorityDotDone` | #D1D5DB | #4B5563 |

Фон нейтрального чипа — наявний `neutralChipBg` (світла #F3F4F6, темна #262A33).
Контраст `metaText` на `neutralChipBg` за оцінкою ≈ 5:1 в обох темах (мінімум 4.5:1). Текст чипів не роби світлішим.

```dart
// tasks_order_design_tokens.dart — додати поля
final Color metaText;
final Color metaExtra;
final Map<TaskPriority, Color> priorityDot;
final Color priorityDotDone;

// light
metaText: Color(0xFF5F6673),
metaExtra: Color(0xFF92400E),
priorityDot: {
  TaskPriority.critical: Color(0xFFDC2626),
  TaskPriority.high: Color(0xFFEA580C),
  TaskPriority.normal: Color(0xFF16A34A),
  TaskPriority.low: Color(0xFF2563EB),
  TaskPriority.someday: Color(0xFF9CA3AF),
},
priorityDotDone: Color(0xFFD1D5DB),

// dark
metaText: Color(0xFF9CA3AF),
metaExtra: Color(0xFFE3BC4E),
priorityDot: {
  TaskPriority.critical: Color(0xFFF87171),
  TaskPriority.high: Color(0xFFFB923C),
  TaskPriority.normal: Color(0xFF4ADE80),
  TaskPriority.low: Color(0xFF60A5FA),
  TaskPriority.someday: Color(0xFF6B7280),
},
priorityDotDone: Color(0xFF4B5563),
```

## Довідкова реалізація (замінює `PriorityChip`, `MetaChip`, `TaskCard` з v1)

Не компілювалася. Адаптуй до моделей і локалізації проєкту.

```dart
enum MetaChipKind { extra, focus, pinned, recurrence, plannedOn }

class _QuietChip extends StatelessWidget {
  const _QuietChip({required this.label, this.leading, this.bg, this.fg});
  final String label;
  final Widget? leading;
  final Color? bg;
  final Color? fg;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<TasksOrderColors>()!;
    final color = fg ?? c.metaText;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: bg ?? c.neutralChipBg, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (leading != null) ...[
          IconTheme(data: IconThemeData(size: 13, color: color), child: leading!),
          const SizedBox(width: 5),
        ],
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

class PriorityChipV2 extends StatelessWidget {
  const PriorityChipV2({super.key, required this.priority, required this.label, required this.isDone});
  final TaskPriority priority;
  final String label;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<TasksOrderColors>()!;
    final loud = priority == TaskPriority.critical && !isDone;
    final dot = isDone ? c.priorityDotDone : c.priorityDot[priority]!;
    return _QuietChip(
      label: label,
      bg: loud ? c.priority(priority).background : null,
      fg: loud ? c.priority(priority).foreground : null,
      leading: Padding(
        padding: const EdgeInsets.only(right: 1), // 5 + 1 = 6 між крапкою і текстом
        child: Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
      ),
    );
  }
}

class MetaChipV2 extends StatelessWidget {
  const MetaChipV2({super.key, required this.kind, required this.label});
  final MetaChipKind kind;
  final String label; // для extra: «+ Понад план»

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<TasksOrderColors>()!;
    return switch (kind) {
      MetaChipKind.extra => _QuietChip(label: label, fg: c.metaExtra),
      MetaChipKind.focus => _QuietChip(label: label, leading: const Icon(Icons.center_focus_strong_outlined)),
      MetaChipKind.pinned => _QuietChip(label: label, leading: const Icon(Icons.push_pin_outlined)),
      MetaChipKind.recurrence => _QuietChip(label: label, leading: const Icon(Icons.repeat)),
      MetaChipKind.plannedOn => _QuietChip(label: label, leading: const Icon(Icons.calendar_today_outlined)),
    };
  }
}

class TaskCardV2 extends StatelessWidget {
  const TaskCardV2({
    super.key,
    required this.title,
    required this.priority,
    required this.priorityLabel,
    required this.metaChips, // уже відсортовані: extra, focus, pinned, recurrence, plannedOn
    required this.isDone,
    required this.onToggleDone,
    required this.doneButton, // _DoneButton з v1 без змін
    this.dueLabel, // null => рядок терміну не показується
    this.dueIsAlert = false,
    this.onTap,
  });

  final String title;
  final TaskPriority priority;
  final String priorityLabel;
  final List<MetaChipV2> metaChips;
  final bool isDone;
  final VoidCallback onToggleDone;
  final Widget doneButton;
  final String? dueLabel;
  final bool dueIsAlert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<TasksOrderColors>()!;
    final dueColor = dueIsAlert && !isDone ? c.alert : c.muted;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isDone ? 0.62 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18), boxShadow: c.cardShadow),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 24 / 18,
                    color: isDone ? c.titleDone : c.title,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    decorationColor: c.titleDone,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  PriorityChipV2(priority: priority, label: priorityLabel, isDone: isDone),
                  ...metaChips,
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  if (dueLabel != null) ...[
                    Icon(Icons.schedule, size: 14, color: dueColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(dueLabel!, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dueColor)),
                    ),
                    const SizedBox(width: 12),
                  ] else
                    const Spacer(),
                  doneButton,
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
```

## Локалізація

| Ключ (пропозиція) | uk | en |
|---|---|---|
| `extraChip` | + Понад план | + Over plan |
| `plannedOnShort` | На {date} | On {date} |
| `plannedOnToday` | На сьогодні | Today |

Рядок `noDueDate` («Без терміну») з v1 у картці більше не використовується.

## Перевірка

- [ ] Назва помітно домінує над чипами в обох темах.
- [ ] Кольоровий фон у чипах лише в «Критичний» (невиконаної задачі).
- [ ] Задача з 4+ позначками показує всі, рядок чипів переноситься.
- [ ] Без дедлайну рядка терміну немає, кнопка стоїть справа.
- [ ] У виконаної критичної задачі чип нейтральний.
