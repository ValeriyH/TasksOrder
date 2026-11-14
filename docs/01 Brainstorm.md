---
tags: [brainstorm, product]
created: 2026-11-12
---
# 01 Brainstorm

## Problem
People collect far more tasks than they can do. Classic to-do apps show the whole pile, which creates guilt and decision fatigue. The user wants to **dump everything in** without thinking, and let the app say: *"today, do these N things"*.

## Core idea
1. **Capture without friction.** Every task gets a priority (scale 1..3, 1..5 or 1..10, configurable) and optionally a due date. Nothing else is mandatory.
2. **Declare capacity, not plans.** The user sets how many tasks they want per weekday (e.g. Mon–Fri: 1, Sat: 3, Sun: 0) and can override single days (holiday, sick day).
3. **The app plans.** It fills today and the following days by priority, respecting capacity. Deadlines can override priority: a low-priority task with a close due date can push a high-priority task later, or temporarily raise a day above its capacity.
4. **The plan is live.** Adding, completing or editing a task recomputes the plan instantly. The user never "re-plans" manually.

## User stories (MVP)
- As a user I can add a task in under 5 seconds: title, priority, optional due date.
- As a user I open the app and see **Today**: the tasks picked for today and why (priority / deadline / pinned / overflow).
- As a user I tick a planned task done and the next one does not jump in (today stays stable); tomorrow is filled from the pool.
- As a user I can mark any task "Focus"; it stays in the plan on its own day, and is also kept in sight in the Focus strip on top of Today, three at a time (D17).
- As a user I use the app in Ukrainian or English, light or dark.
- As a user I can look ahead (**Plan**) and see which day each task lands on.
- As a user I can set capacity per weekday and the priority scale in **Settings**.
- As a user I can see all tasks (**Tasks**), sorted by priority, including ones that do not fit the planning horizon.
- As a user I am warned when deadlines cannot be met with the current capacity.
- As a user I never lose an overdue task: it is planned by its priority like a task without a date, and stays in Focus with an "overdue" badge until I do it or move its date (D18).
- As a user I can do a task from a later day ahead of time without today's list changing (D19).

## Feature list

### MVP (v0.1)
- Tasks: title, notes, priority, due date, Focus flag, pin date, status (active / done), soft delete
- Settings: priority scale (3 / 5 / 10), capacity per weekday, overflow (+1/+2/+3), planning horizon, day start hour, language, theme
- Planner: priority fill + deadline forcing + urgency boost + overflow + at-risk flags + Focus view
- Screens: Today, Plan (upcoming days), Tasks (all), Add/Edit task, Settings, Done list
- Ukrainian and English UI, light and dark theme
- Local storage only (SQLite), no account, no network

### v0.2
- Move a task to another day straight from the Plan screen (the pin date itself is in the editor from v0.1); day capacity overrides (calendar); Trash with restore
- Overdue / at-risk resolution actions (move due date, drop, raise capacity)
- Daily morning notification with today's list
- Backup / restore as JSON

### Later ideas (parking lot)
- "Not before" date (snooze) and recurring tasks
- Effort estimate (S/M/L) and capacity in "points" instead of task count
- Projects / tags, subtasks
- Stats: completed per week, streaks
- Home-screen widget
- Sync between devices (would require accounts; keep out until the local app is solid)
## Key decisions
| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Priority 1 = highest. A priority is a fixed level of the ten-level table** (changed 2026-11-14, ADR-17): Critical is always 2, High 3, Normal 5, Low 7, Someday 8, whatever the scale. The scale (3, 5 or 10) only chooses which levels the app offers: scale 3 is Critical / Normal / Low, scale 5 adds High and Someday, scale 10 offers all ten. A task keeps its level when the scale changes; a level the scale does not offer is shown as the nearest one it does (the higher on a tie) and stays stored as it is. Shown as the **name only**, e.g. *Critical*, with the colour of the level; the order is visible from the sorting and the colours. Every level is planned the same way inside the daily capacity; "do it today regardless of capacity" is a pin (D17). Label tables below. | Owner 2026-11-14, after the device test: with "the number is the position in the scale" a change 5 → 10 turned Normal (3) into High (3), and 10 → 5 squeezed it again, so a round trip raised every task. Fixed levels make any scale change lossless. The number is not shown because on scale 3 it would read 2, 5, 7. Earlier (2026-11-12/13): "Label (n)" with the position in the scale. |

### Priority labels (D1)
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

A new task gets Normal (5) on every scale. Level 8 in Ukrainian was "Якось" on scale 10 and "Колись" on scale 5; since a level has one name everywhere it is "Якось" (owner, 2026-11-14). Colours (changed 2026-11-13, owner: amber for the ordinary level looked like a warning) go by the position of a level in the scale: red for the first, **green for Normal**, blue for the last; between them orange (raised) and teal (lowered), so scale 5 is red, orange, green, teal, blue and scale 10 uses the steps in between. Labels are localisation keys (`priority.s5.3` = the third level of scale 5), so wording can be tuned later without touching code.
| D2 | **The plan is derived, never stored.** Only tasks, settings and manual pins are persisted; the plan is a pure function of them. A **cache** of the last plan may be written later only for consumers that cannot compute it (home-screen widget, notification). | No sync bugs between "stored plan" and reality. Any change (new task, done, settings) simply recomputes. Cheap for hundreds of tasks. Confirmed by owner. |
| D3 | **Today is stable.** Completing a task today does not pull the next task into today. | The user asked for "N per day", not "always N visible". Pulling tasks in would make the day endless. A "do one more" button can be added later. Exception: deadline-forced slots refill (D16). Only completions from today's list use up a slot (D19). |
| D4 | **Deadlines win over priority, but only when forced.** The planner computes the minimum number of due-dated tasks that must happen today to still meet every deadline (earliest-deadline-first feasibility). | Exactly the "lower priority can push a higher one" behaviour, without making every due date dominate. |
| D5 | **Overflow is bounded.** A day can exceed its capacity by at most `maxOverflowPerDay` (default 1), only because of deadlines. Beyond that, tasks spill and are flagged **at risk**. | The user asked for "2 instead of 1" but not for an unbounded pile. At-risk flags turn an impossible situation into something actionable. |
| D6 | **Zero-capacity days stay empty.** No overflow lands on a rest day; deadlines falling on such days are forced earlier. | Rest days were requested explicitly. |
| D7 | _Overdue part superseded by D18 (2026-11-13); the first sentence still holds._ **Not-done planned tasks return to the pool; overdue tasks go to the Today queue.** At the day boundary the plan is recomputed from the new "today". A task whose due date has passed is no longer planned into slots: it is **automatically part of the Today queue** (D11) with an *overdue* badge, outside capacity, until it is done or its due date is moved or cleared. | Owner 2026-11-13: in other apps an overdue task either gets lost in the pile or blocks the plan. In the Today queue it is always visible (top 3 or "+N more"), never eats a planned slot and never produces daily at-risk noise. No stored state: the rule is derived from `dueDate < today`, consistent with D2. |
| D8 | **Local-first, Android only, no backend.** | Fastest path to a usable app. Flutter keeps iOS possible later. |
| D9 | **Flutter + Riverpod + drift (SQLite).** Planner lives in a pure Dart layer with no Flutter imports. | The planner is the product; it must be unit-testable in milliseconds. Drift gives reactive streams so UI recomputes automatically. |
| D10 | **Deadlines are spread, not crammed.** Two mechanisms: (a) *hard* — EDF feasibility forcing guarantees every deadline is met and automatically pulls tasks earlier when capacity before the due date is insufficient (4 tasks due in 2 days with capacity 1/day → 2 today, 1 tomorrow, 1 on the due day); (b) *soft* — **urgency boost**: a task due within 7 days is treated one priority level higher, within 2 days two levels higher (levels of the scale in use: Normal → High → Critical on scale 5, ADR-17), so due-dated tasks start competing for slots early instead of all landing on the due day. Thresholds configurable. | Owner's concern: "deadline arrives and all 4 are active at once". (a) prevents the impossible case, (b) prevents the unpleasant case. Details in [[04 Planner Algorithm]]. |
| D11 | _Superseded by D17 (2026-11-13)._ **"Today" flag = a user-pinned queue outside the daily capacity.** Any task, whatever its priority, can be flagged *Today*. Flagged tasks form the **Today queue**: shown in their own section at the top of the Today screen, at most `todayVisibleLimit` (3) visible at a time, the rest wait in the queue ("+2 more"). Unlike the planned slots, the Today queue **refills**: close one of five flagged tasks and the next one appears, still three visible. Flagged tasks do not consume capacity, are not placed on any day by the planner and are ignored by deadline math. The flag persists across midnight until the task is done or unflagged. **Overdue tasks join the queue automatically** (D7). Queue order: **priority first**, then due date (so overdue ones lead within a priority), then when it was flagged. | Owner 2026-11-12: priority alone should not force a task onto the board; a Critical task may wait for its slot, a Normal task may need to happen today. The visible limit keeps the board calm; the refill rule exists because flagged tasks are a conscious commitment, not an automatic plan. |
| D13 | **Bilingual (Ukrainian, English) and light/dark from the first screen.** Strings live in ARB files. Both language and theme are user-selectable in Settings; the **default is the device setting** (language: system locale, falling back to English if it is neither uk nor en; theme: system light/dark). | Owner requirement. Retrofitting localisation is tedious; starting with it costs nothing. |
| D14 | **Two statuses only: active and done. Deleting is a soft delete (trash).** There is no separate "dropped/archived" status. Deleted tasks disappear from every list, can be restored from a *Trash* screen for 30 days, then are purged. | Owner asked what an archive would be for if deletes are soft anyway. Nothing: one mechanism is enough. Trash = the soft-deleted rows, which also serve as sync tombstones (D12). |
| D15 | **Configurable day boundary.** `dayStartHour` (default 0 = midnight) shifts when "today" rolls over; 04:00 means a task finished at 01:00 still counts as yesterday's. | Owner requested it configurable. |
| D16 | **Deadline slots refill, and an unachievable plan is shown as such.** Tasks that *must* happen today because of a deadline refill: at most `capacity + maxOverflowPerDay` are visible, and closing one pulls in the next (capacity 2, overflow 1, five tasks due today → three shown; close one → the fourth appears). Slots filled by plain priority still do not refill (D3). Whatever cannot fit before its due date is **at risk**; when a plan has at-risk tasks the Today screen highlights it ("N tasks will not make their deadline") and lists them, so the user can decide which ones matter: do extra, move a date, or drop. | Owner 2026-11-13: with five tasks due today and capacity 2, three of them will be late whatever happens. The app must say so up front instead of silently showing two, and must keep offering the next one if the user keeps going. |
| D12 | **Sync-ready from day one, sync-free for now.** Every row has a UUID, `updatedAt` (UTC) and a nullable `deletedAt` (soft delete, tombstone). Planning settings (scale, capacity) are kept separate from device settings (theme). Repositories are interfaces; a future sync engine sits behind the same interfaces. No user ids, accounts or network in MVP. | Owner's future wishes: multi-device sync, then a "family group" where partners see each other's load and queue tasks for each other. These three fields are what any CRDT/last-write-wins sync needs; adding them later means a painful migration, adding them now costs nothing. |
| D17 | **Focus replaces the Today flag: a view, not a queue.** Any task can be marked *Focus* (`isFocused`). A focused task **stays in the pool** and is planned like every other task (priority, deadline forcing, boost, capacity). Focus is an alternative view over the same tasks: the **Focus strip** on top of the Today screen lists focused and overdue (D18) tasks that are *not* already on today's list, at most `focusVisibleLimit` (3) at a time with "+N more", ordered by priority, then due date (so overdue ones lead within a priority), then when the task was focused. A focus task that is on today's list is shown only there. Everywhere (Today, Plan, Tasks) such a task carries the focus mark; in the strip it also shows the day it is planned for. Focus changes no capacity or deadline math. "Do it on this day whatever the capacity" is a **pin**; the pin date is in the task editor from v0.1. | Owner 2026-11-13: the Today queue lived for days and became a second backlog, so "Today" was the wrong name; flagged tasks vanished from the plan and lost their deadline protection. Keeping them in the plan is honest, and the strip still keeps them in sight. The command "do it today above the limit" is lost on purpose; a pin covers it. |
| D18 | **Overdue tasks are plain pool tasks that stay in Focus.** Once `dueDate < today` the planner ignores the due date: no forcing, no boost, never *at risk*; the task competes by priority only, like a task without a date. It is automatically in Focus with an "overdue by N days" badge until it is done or its due date is moved or cleared. Derived from the date, nothing stored (D2). | Owner 2026-11-13: a missed deadline has nothing left to protect, so it must neither block the plan nor produce daily at-risk noise; Focus keeps it visible. One pool, no separate queue. Accepted consequence: a low-priority task can drop back in the plan the day after its deadline. |
| D19 | **Only completions from today's list use up today's capacity.** Ticking a task that was on today's list leaves its slot empty (D3). Ticking any other task (from the Focus strip, Plan or Tasks) leaves today's list as it is; the slot it held on a later day is planned again. The task stores `completedOnPlan`, set at completion, because the plan itself is not stored (D2). There is no "earned free day": a day is kept free with a day override. | Owner 2026-11-13: "if it is Tuesday and I closed Thursday's task, why move anything?". Before, every non-flagged completion lowered today's capacity, so doing work ahead pushed a task out of today. |

## Open questions for the owner
All answered as of 2026-11-13:
- Priority direction: 1 = highest, shown as labels, scale 5 by default (D1).
- Plan is derived; cache only for widgets/notifications if ever needed (D2).
- Deadlines win and are spread: EDF forcing + urgency boost (D10). Boost thresholds stay 7 / 2 days until real use shows otherwise.
- "Today" flag with a refilling queue, 3 visible (D11). Replaces the earlier "Critical tier" idea.
- Overflow is a setting: +1 (default), +2 or +3 (D5).
- Rest days stay empty (D6). Planned slots never auto-refill (D3).
- Day boundary configurable, default midnight (D15).
- No archive: delete = trash with restore (D14).
- Local-only now, sync-ready rows (D12). Bilingual + themes (D13).

## Future: sync and family group (not scheduled)
Hooks the MVP keeps open, see D12:
- Tasks get `ownerId` and `assigneeId` when accounts arrive; the local user is the default owner.
- A partner can **propose** a task into my queue: new status `proposed`, I accept (→ active with my priority) or decline.
- Load visibility: the partner sees my plan summary (n/capacity per day), not task contents, unless shared.
- Sync engine: last-write-wins on `updatedAt` per row is enough for a two-person family; tombstones via `deletedAt`.

## Glossary
- **Capacity** — number of tasks the user wants on a given day.
- **Pool** — all active tasks not yet placed.
- **Focus** — a mark that keeps a task in sight; the task stays in the plan (D17). Replaces the Today flag.
- **Focus strip** — top of the Today screen: focused and overdue tasks that are not on today's list, 3 visible + "+N more", sorted by priority (D17).
- **Overdue** — `dueDate < today`; planned as a task without a date and automatically in Focus (D18).
- **Critical** — just the label of priority 1 on the default scale; planned like any other level.
- **Urgency boost** — temporary priority raise for tasks whose due date is close (D10).
- **Forced** — a task placed on a day because of deadline feasibility, not priority.
- **Overflow** — tasks on a day above its capacity (deadline-driven, bounded by `maxOverflowPerDay`).
- **At risk** — a task whose due date cannot be met with current capacity + overflow.
- **Pinned** — task manually fixed to a date by the user.
- **Horizon** — how many days ahead the planner fills (default 90). Tasks that do not fit are "Later".
