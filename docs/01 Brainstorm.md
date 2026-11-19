---
tags: [brainstorm, product]
created: 2026-11-12
updated: 2026-11-20
---
# 01 Brainstorm

The product: what it is for, what it does today and the decisions it rests on. Decisions keep their numbers (D1–D23); replaced ones are in [[Superseded decisions]], the story of how each came about in [[History]].

## Problem
People collect far more tasks than they can do. Classic to-do apps show the whole pile, which creates guilt and decision fatigue. The user wants to **dump everything in** without thinking, and let the app say: *"today, do these N things"*.

## Core idea
1. **Capture without friction.** Every task gets a priority and optionally a due date. Nothing else is mandatory.
2. **Declare capacity, not plans.** The user sets how many tasks they want per weekday (e.g. Mon–Fri: 1, Sat: 3, Sun: 0) and can override single days (holiday, sick day).
3. **The app plans.** It fills today and the following days by priority, respecting capacity. Deadlines can override priority: a low-priority task with a close due date can push a high-priority task later, or temporarily raise a day above its capacity.
4. **The plan is live.** Adding, completing or editing a task recomputes the plan instantly. The user never "re-plans" manually.

## User stories
- Add a task in under 5 seconds: title, priority, optional due date (quick add on Today; the full editor for the rest).
- Open the app and see **Today**: the tasks picked for today and why (priority / deadline / pinned / over plan).
- Tick a planned task done and the next one does not jump in (today stays stable); tomorrow is filled from the pool.
- Mark any task **Focus**: it stays planned on its day and is also kept in sight on top of Today, three at a time.
- Never lose an overdue task: it is planned by priority and stays in Focus until done or its date is moved.
- Do a task from a later day ahead of time without today's list changing.
- Look ahead (**Plan**) and see which day each task lands on, with the load of each day.
- See all tasks (**Tasks**) with filters, including the ones that do not fit the horizon (Later) and the done ones.
- Be warned when deadlines cannot be met with the current capacity.
- Make a task repeat and see its future repeats in the Plan, so the load of the coming weeks is honest.
- Say that a task is small or large, so two small ones share a day and a large one gets a day with room.
- Limit a task to some days of the week ("only Sat").
- Use the app in Ukrainian or English, light or dark; see today's tasks in a home-screen widget and a morning notification.

## Features (0.8.1)
- **Tasks:** title, notes, priority, size, due date, Focus, pin ("Do on this day"), Not before, allowed days, repeat; active / done; soft delete to the Trash (30 days).
- **Planner:** priority fill (first fit by size), deadline forcing, urgency boost, bounded overflow, at-risk flags, pins, release dates, ghosts of repeats, allowed days, Focus view.
- **Screens:** Today (progress, Focus, Planned, quick add), Plan (days with capacity pills and free slots, day overrides), Tasks (Active, Focus, With due date, Recurring, Later, Done), editor, task menu (skip, postpone, pin, move or clear an overdue date, edit), Trash, Settings.
- **Card:** title, chips (priority dot, focus, pin, over plan, repeat, planned day, size, days…), expandable notes, due line, Done / Completed button.
- **Settings:** priority scale (3 / 5 / 10), capacity per weekday, overflow +1/+2/+3, horizon, day start hour, language, theme, reason badges, morning notification time; backup / restore to a JSON file.
- **Android extras:** home-screen widget, morning notification.
- Local storage only (SQLite; IndexedDB on the web), no account, no network.

## Decisions
**D1 — Priority is a fixed level of a ten-level table; 1 = highest.** Critical is always 2, High 3, Normal 5, Low 7, Someday 8, whatever the scale. The scale (3, 5, 10) only chooses which levels the app offers; a task keeps its level when the scale changes, and a level the scale does not offer is shown as the nearest one (the higher on a tie). Shown as the name only, with the colour of the level. Every level is planned the same way inside the capacity; "do it today regardless" is a pin. A new task is Normal. _Why:_ positions in the scale made every scale change lossy (ADR-17); the number would read 2, 5, 7 on scale 3.

| Level | en | uk | Scale 3 | Scale 5 | Scale 10 |
|---|---|---|---|---|---|
| 1 | Catastrophic | Катастрофічний | | | ✓ |
| 2 | Critical | Критичний | ✓ | ✓ | ✓ |
| 3 | High | Високий | | ✓ | ✓ |
| 4 | Elevated | Підвищений | | | ✓ |
| 5 | Normal | Звичайний | ✓ | ✓ | ✓ |
| 6 | Minor | Понижений | | | ✓ |
| 7 | Low | Низький | ✓ | ✓ | ✓ |
| 8 | Someday | Якось | | ✓ | ✓ |
| 9 | Whenever | Хтозна-коли | | | ✓ |
| 10 | Never | Ніколи | | | ✓ |

Colours are computed, not stored: `PriorityLabels.color(level, scale)` goes by the position of the level in the scale over five anchors, red `#D32F2F` (first), orange `#F57C00`, green `#388E3C` (Normal), teal `#0097A7`, blue `#1976D2` (last), so the same level can differ between scales (Critical is red on 3 and 5, red-orange on 10). Chip shades per theme come from `PriorityShade` (`lib/app/app_colors.dart`) with at least 4.5:1 contrast (tested). On the card only levels 1–2 have a coloured chip; the others show a dot of the level's colour on a grey chip; a done card is all grey.

**D2 — The plan is derived, never stored.** Only tasks, settings, day overrides and pins are persisted; the plan is a pure function of them. A cache is written only for consumers that cannot compute it (widget, notifications). _Why:_ no drift between a stored plan and reality; recomputing is cheap.

**D3 — Today is stable.** Completing a task from today's list does not pull the next task into today. Exception: deadline-forced slots refill (D16). _Why:_ the user asked for "N per day", not an endless day.

**D4 — Deadlines win over priority only when forced.** The planner computes the minimum number of due-dated tasks that must happen today to meet every deadline (earliest-deadline-first feasibility).

**D5 — Overflow is bounded.** A day can exceed its capacity by at most `maxOverflowPerDay` (+1 default, up to +3), only because of deadlines (and a top-level large task, D21). Beyond that, tasks spill and are flagged **at risk**.

**D6 — Rest days stay empty.** No overflow on a day with capacity 0; deadlines falling there are forced earlier. Pins are honoured.

**D7 — At the day boundary unfinished planned tasks return to the pool** and the plan is recomputed from the new today. (Overdue handling: D18.)

**D8 — Local-first, Android first, no backend.** Flutter keeps iOS possible.

**D9 — Flutter + Riverpod + drift (SQLite); the planner is pure Dart** with no Flutter imports, unit-tested in milliseconds.

**D10 — Deadlines are spread, not crammed.** (a) Hard: EDF forcing pulls tasks earlier when the capacity before a due date is short (4 tasks due in 2 days, capacity 1 → 2 today, 1 tomorrow, 1 on the day). (b) Soft: **urgency boost** — due within 7 days → one level higher, within 2 days → two levels (levels of the scale in use); thresholds are settings. _Why:_ otherwise all due tasks land on the due day.

**D12 — Sync-ready, sync-free.** Every row has a UUID, `updatedAt` (UTC) and a nullable `deletedAt`; planning settings are separate from device settings; repositories are interfaces a future sync engine can sit behind. No accounts or network.

**D13 — Ukrainian and English, light and dark, from the first screen.** ARB strings; language and theme default to the device and can be chosen in Settings (an unknown device language falls back to English).

**D14 — Two statuses: active and done.** Delete is a soft delete: the Trash, restorable for 30 days, then purged; the same rows are sync tombstones.

**D15 — Configurable day boundary.** `dayStartHour` (default midnight); at 04:00 a task finished at 01:00 counts for the day before.

**D16 — Deadline slots refill; an unachievable plan is shown as such.** Tasks that must happen today because of a deadline refill up to `capacity + overflow`; what cannot make its date is at risk, and Today says "N tasks will not make their deadline" with the list.

**D17 — Focus is a view, not a queue.** A focused task stays in the pool and is planned like any other. The Focus section on Today lists focused and overdue tasks that are not on today's list, three visible with "+N more", by priority, due date, focus time; it shows the day each is planned for. Focus changes no capacity or deadline math; "do it on this day whatever the capacity" is a pin.

**D18 — Overdue tasks are plain pool tasks that stay in Focus.** Once `dueDate < today` the due date is ignored by the planner (no forcing, boost or at-risk); the task competes by priority and carries "overdue by N days" in Focus until done or its date is moved. Derived from the date.

**D19 — Only completions from today's list use up today's capacity.** Ticking any other task leaves today's list as it is; its later slot is planned again. The completion stores `completedOnPlan` (the plan is not stored). A free day is a day override, not an earned reward.

**D20 — Recurring tasks: one stored instance per series, the rest derived.** Rules: every N days / weeks / months / years, by schedule (from an anchor; the 31st falls back to the month's last day) or from completion; or on weekdays. When the instance is completed or skipped, the next one is created in the same write; later repeats inside the horizon are **ghosts** computed by the planner (they take slots, cannot be ticked). The date of a repeat goes where the task keeps its date: pin, else due date, else Not before. Missed repeats do not pile up. A series ends only by hand. A rule from completion has no ghosts (ADR-24). _Why:_ resetting one row would lose the done record D3/D19 need; storing the horizon needs writes at every rollover.

**D21 — Task size: small, normal, large = ½, 1, 2 slots; a task is done within one day.** Capacity stays "normal tasks per day"; the task stores its weight in half-slots (1, 2, 4). First fit by priority: a large task waits for the first day that can hold it while lighter tasks go ahead. A task never weighs more than the biggest weekday. A large task of level 1–2 first in the queue may take a too-small day with overflow (one a day, never a rest day). Bigger jobs are split by hand. _Why:_ paying bills and re-roofing are not the same; hours would be a chore; spreading over days collides with other rules.

**D22 — Task cards with a Done button; done tasks stay in sight.** A task is a card (title, chips, due line, Done / Completed); a tap opens the task menu on every list (a ghost opens the task). A task done today stays dimmed at the end of its section until the day ends; on the Plan a task done ahead stays on its planned day until that day is past; in Tasks a done task stays until the filter changes. No Undo snack bar. Tasks filters: Active, Focus, With due date, Recurring, Later, Done. The owner's mockups are a reference, not a contract (no due times, the app's own priority colours). The quiet card v2 (`CARD_SPEC.md`) puts the title first.

**D23 — Allowed days.** A task can carry a set of weekdays ("only Thu and Fri"); it is placed only on those days, competes by priority there, and after a missed day simply lands on the next allowed one (nothing stored, nothing in Focus). With a due date it is forced on its last allowed day before the date; overdue → Focus as usual. A pin wins (a past pin moves to the nearest allowed day). It can be ticked on any day; repeats carry the set. No banners. _Why:_ offices with opening days and weekend chores; pins and weekday repeats describe one week or make a series out of one job.

## Glossary
- **Capacity** — how many normal tasks the user wants on a day; a day override replaces it for one date.
- **Slot / weight** — one normal task of capacity; weights are in half-slots (small 1, normal 2, large 4).
- **Pool** — active tasks not yet placed.
- **Focus** — a mark that keeps a task in sight; the task stays planned (D17).
- **Overdue** — `dueDate < today`; planned as a task without a date, automatically in Focus (D18).
- **Urgency boost** — a temporary raise by one or two levels for a task whose due date is close (D10).
- **Forced** — placed on a day because of deadline feasibility, not priority.
- **Over plan / overflow** — tasks on a day above its capacity, bounded by `maxOverflowPerDay`.
- **At risk** — a task whose due date cannot be met with current capacity + overflow.
- **Pinned** — fixed to a date by the user ("Do on this day").
- **Not before** — the first day the planner may place a task on (snooze; also set for the next instance of a series).
- **Allowed days** — the weekdays a task may be planned on (D23).
- **Horizon** — how many days ahead the planner fills (default 90); tasks that do not fit are **Later**.
- **Series / instance / ghost** — a recurring task over time / one stored task of it (at most one active) / a future repeat computed by the planner, not stored (D20).
