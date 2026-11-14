---
tags: [algorithm, planner]
created: 2026-11-12
updated: 2026-11-13
---
# 04 Planner Algorithm

The planner is a **pure function**: same inputs → same plan. No randomness, no clock access (today is an input).

```
Plan plan({
  required List<Task> activeTasks,
  required Settings settings,
  required Map<LocalDate, DayOverride> overrides,
  required LocalDate today,
  int completedTodayCount = 0,   // tasks completed today from today's list (D19)
})
```

## Two kinds of tasks
Every active task is planned; there is no queue outside the pool (D17).

| Kind | Who | Behaviour |
|------|-----|-----------|
| **Due-dated** | `dueDate >= today` | Compete by *effective* priority (urgency boost, D10) and are **forced** when the deadline would otherwise be missed. |
| **Plain** | no due date, **or overdue** (`dueDate < today`, D18) | Compete by priority only. Never forced, never boosted, never at risk. |

An overdue task is planned exactly like a task without a date: its deadline is gone, so there is nothing left to protect. It is kept in sight by the Focus view instead.

Priority 1 ("Critical") is an ordinary level: it wins the priority fill but waits for a slot like everything else. "Do it on this day whatever the capacity" is a pin.

## Focus: a view, not a queue
`Plan.focus` lists the tasks with `isFocused == true` **or** `dueDate < today`. It is built from the same tasks the day loop places and changes nothing in the plan: no capacity, no deadline math (D17).
- Order: priority, then `dueDate` (nulls last; overdue therefore first within a priority), then `focusedAt` (nulls last), then `createdAt`.
- Each entry carries `focused`, `overdueDays` and `plannedDate` (the day the task landed on, `null` = later).
- The **Focus strip** on the Today screen is `visibleFocus`: the entries whose `plannedDate` is not today, first `focusVisibleLimit` (3); `hiddenFocusCount` is the "+N more" counter. A focus task that is on today's list is shown only there, with the focus mark.
- An overdue task leaves Focus only when it is done or its due date is moved to today or later / cleared (unless it is also focused by the user).

## Inputs and derived values
- `capacity(d)` = `overrides[d]?.capacity ?? settings.weeklyCapacity[d.weekday]`. For `today`, subtract `completedTodayCount` (floor 0) so Today stays stable after ticking tasks (D3).
- `completedTodayCount` = tasks with `completedOnPlan == true` whose `completedAt` falls on today (`Planner.countCompletedToday`). `completedOnPlan` is set when the task is ticked: true if it was on today's list at that moment. A task done ahead of its day (from the Focus strip, the Plan or the Tasks screen) does not count: today's list stays as it is and the slot it held later is planned again (D19). Only today is "sticky"; every other day is recomputed.
- Rest days never receive tasks (D6). `hardLimit(d)` = `baseCapacity(d) == 0 ? 0 : baseCapacity(d) + settings.maxOverflowPerDay`, where `baseCapacity` is the value **before** `completedTodayCount` is subtracted. So `completedTodayCount` only limits the priority fill; deadline-forced tasks keep refilling up to the hard limit (D16): capacity 2, overflow 1, five tasks due today → three shown, and each completion pulls in the next one.
- `effDue(t)` = `t.dueDate`, or none when the task is overdue (D18). So `effDue` is never in the past and no clamping is needed; a task due *today* is simply forced today.
- `effPriority(t, d)` — urgency boost (D10):
  ```
  if effDue(t) == null: return t.priority
  slack = effDue(t) - d                      // days
  boost = slack <= settings.urgencyNearDays ? 2      // default 2
        : slack <= settings.urgencySoonDays ? 1      // default 7
        : 0
  levels = levels(settings.priorityScale)   // e.g. scale 5: [2, 3, 5, 7, 8]
  i = index of the level nearest to t.priority (the higher on a tie)
  return min(t.priority, levels[max(0, i - boost)])
  ```
  The steps are levels of the scale in use (ADR-17): on scale 5 Normal (5) becomes High (3), then Critical (2); on scale 10 Elevated (4), then High (3). A boost never lowers a priority, so Catastrophic (1) on scale 5 stays 1.
- Pool ordering (used whenever "next by priority" is needed), evaluated for the day `d` being filled:
  1. `effPriority(t, d)` ascending (1 first)
  2. original `priority` ascending — a boosted task joins a tier but does not overtake that tier's originals
  3. `effDue` ascending, `null` last
  4. `createdAt` ascending

## Day loop
```
pool = activeTasks                                     // overdue ones without their due date

for d in today .. today + horizon - 1:                // horizon counts today
    day = PlannedDay(d, capacity(d))

    // 1. Pinned: kept outside the pool until their day, placed whatever the
    //    capacity (also on a rest day: an explicit pin beats D6), never trimmed
    for t in pinned where t.pinnedDate == d or (t.pinnedDate < today and d == today):
        place(t, reason: pinned)

    if hardLimit(d) == 0: continue                    // rest day

    // 2. Deadline-forced (minimum needed to keep every deadline feasible)
    for t in forcedToday(pool, d):
        place(t, reason: deadline)

    // 3. Priority fill up to capacity (not above), using effPriority(t, d)
    while day.entries.length < capacity(d) and pool not empty:
        place(pool.firstFor(d), reason: priority)

    // Flags
    for entry at index >= capacity(d): entry.overflow = true
    trim(day, hardLimit(d))        // tail goes back to the pool; it will be atRisk when placed after effDue

later = whatever remains in pool

focus = activeTasks where isFocused or dueDate < today,
        sorted by (priority, dueDate nulls last, focusedAt nulls last, createdAt)
        -> FocusEntry(taskId, focused: isFocused,
                      overdueDays: max(0, today - dueDate), plannedDate: day it was placed on)
```
`place()` removes the task from the pool and appends an entry. An entry gets `atRisk = true` when `d > effDue(t)`; an overdue task has no `effDue`, so it is never at risk.

## Deadline forcing — `forcedToday(pool, d)`
Unit-size tasks with per-day capacities: *earliest deadline first* is optimal for feasibility, so the minimum number of due-dated tasks that must be done on `d` can be computed directly.

```
dueTasks = pool where effDue != null, sorted by (effDue asc, priority asc, createdAt asc)
if dueTasks empty: return []

forcedCount = 0
for each distinct D in effDue values (ascending):
    need(D)  = count of dueTasks with effDue <= D
    avail(D) = sum over x in (d+1 .. D) of max(0, capacity(x) - pinnedOn(x))
    forcedCount = max(forcedCount, need(D) - avail(D))

return first forcedCount tasks of dueTasks   (EDF order)
```
- `avail` uses **base** capacity, not overflow: overflow is a last resort, so the planner is pessimistic about the future and may force a task a day early rather than rely on overflow later. This is intentional and is what spreads a cluster of deadlines over the preceding days.
- Plain tasks (overdue ones included) are never forced; they only fill leftover slots by priority.
- Because today's priority fill only consumes today's slots (which `avail` never counted), it cannot break future feasibility.
- A focused task is an ordinary pool task: with a due date it is forced and boosted like any other.

## Why two mechanisms (hard forcing + soft boost)
Forcing alone meets deadlines but is *lazy*: with comfortable capacity it leaves due tasks to the last feasible day, so the user experiences "the deadline came and everything is due at once". The boost makes due tasks win slots early when capacity allows; forcing is the safety net when it does not.

## Flags and reasons (what the UI shows)
| Flag | Meaning | UI |
|------|---------|----|
| Focus | focused by the user or overdue; also planned on a day | "Focus" strip on top of Today with the tasks that are not on today's list: 3 visible, "+N more" counter, "planned for <day>" hint; the focus mark on the task wherever it is listed; overdue tasks get a red "overdue by N days" badge and actions *move due date / clear due date* |
| `reason = priority` | normal pick | no badge |
| `reason = deadline` | placed because of a due date, possibly pushing a higher priority later | badge "due" |
| `reason = pinned` | user fixed the date | badge "pinned" |
| `overflow` | above the day's capacity | day banner "1 extra because of deadlines" |
| `atRisk` | placed after its due date (impossible with current capacity) | red badge + Plan header "N tasks at risk"; Today screen banner "N tasks will not make their deadline" opening the list (`Plan.hasAtRisk`, D16) |

## Worked example 1 — priority vs deadline (tight capacity)
The priorities in the examples are positions on scale 5: 1 Critical, 2 High, 3 Normal, 4 Low, 5 Someday. Since ADR-17 a task stores the level of the ten-level table (2, 3, 5, 7, 8); the order and the boost steps are the same, and `planner_test.dart` maps the numbers so.

Settings: scale 5, capacity Mon–Fri 1, Sat 3, Sun 0, overflow 1, boost thresholds 7 / 2. Today = Mon 2026-11-16.

| Task | Priority | Due |
|------|----------|-----|
| K | 3 (Normal), **Focus** | – |
| A | 2 (High) | – |
| F | 2 (High) | – (created after A) |
| B | 3 (Normal) | – |
| E | 3 (Normal) | Sat 21 |
| C | 4 (Low) | Tue 17 |
| D | 5 (Someday) | Wed 18 |

Result:
| Day | Tasks | Why |
|-----|-------|-----|
| Mon 16 | A | forced = 0 (C fits Tue, D fits Wed, E fits by Sat). C is boosted to tier 2 (slack 1) but A, F are originals of tier 2 → **A** by `createdAt`. K (Normal) waits like any Normal task; the Focus strip shows it every day until Saturday. |
| Tue 17 | C *(due)* | need(17)=1, avail=0 → forced. **F (High) is pushed by C (Low).** |
| Wed 18 | D *(due)* | need(18)=1, avail=0 → forced. |
| Thu 19 | E | E is due in 2 days → boost 2 → tier 1 (3 − 2), ahead of F (High, tier 2) |
| Fri 20 | F | priority |
| Sat 21 | K, B | priority, older first; one Sat slot stays empty. K is on today's list now, so it leaves the strip. |
| Sun 22 | – | rest day |

Without the boost (thresholds 0 / 0) only Thu and Fri swap: **F** on Thu by priority, **E** on Fri (same priority as B, but it has a due date). Forcing alone already spreads the deadlines here; the boost only decides who goes first among the tasks that are not forced. It matters more when there is spare capacity (example 2).

_Corrected 2026-11-13 (T-108): the first version of this table kept E in tier 2 on Thu/Fri, which contradicts the `effPriority` formula; the formula is the rule. Changed 2026-11-13 (T-111): K is focused instead of Today-flagged, so it is planned (Sat) instead of sitting outside the plan._

## Worked example 2 — urgency boost with spare capacity (D10b)
Capacity 2/day Mon–Fri. Today Mon. Tasks: A, F (High), B, G, H (Normal) without due; L (Low) due Thu.

| | Forcing only | Forcing + boost |
|--|--|--|
| Mon | A, F | A, F (L slack 3 → tier 3, behind originals B, G, H) |
| Tue | B, G | **L**, B (L slack 2 → tier 2, no tier-2 originals left) |
| Wed | H, L (last feasible day, not even forced) | G, H |
| Thu | – | – |

The boost moves L from the last possible moment to two days before the deadline while the queue is calm, which is the "do not pile up on the due day" behaviour the owner asked for. Thresholds (7/2) tune how early that happens.

## Worked example 3 — spreading a deadline cluster (D10a)
Capacity 1/day, overflow 1. Today Mon. Four Low tasks P, Q, R, S all due Wed. Plus one High task A without due.
- Mon: need(Wed)=4, avail(Tue, Wed)=2 → forced 2 → **P, Q** (Q overflow). A is pushed.
- Tue: need=2, avail(Wed)=1 → forced 1 → **R**.
- Wed: **S** (forced).
- Thu: **A**.
With overflow 0: hardLimit 1 everywhere → Mon P, Tue Q, Wed R, and S lands on Thu flagged **at risk, visible on Monday already**, so the user can react (drop one, move a date, raise capacity).

## Worked example 4 — rest day
Capacity Sun 0. Task due Sun. On Sat: need(Sun)=1, avail(Sun)=0 → forced on Sat (or earlier if Sat is full). Sunday is never used.

## Test scenarios (table-driven, `test/domain/planner_test.dart`)
1. Empty pool → every day empty, `later` empty, `focus` empty.
2. No due dates, capacity 1 → tasks in priority order, one per day, ties by `createdAt`.
3. Capacity per weekday respected; Sun 0 skipped.
4. DayOverride replaces weekday capacity for that date only.
5. Worked example 2 → boosted result (L on Tue); with thresholds 0/0 → forcing-only result (L on Wed).
6. Worked example 1 → exact day/task map (Thu E, Fri F, Sat K + B); with thresholds 0/0 → Thu F, Fri E. K is in `focus` with `plannedDate` Sat.
7. Worked example 3 → 2/1/1 spread; overflow flag on Q.
8. Worked example 3 with overflow 0 → S on Thu with `atRisk`, listed in `atRiskTaskIds`.
9. Two tasks due today, capacity 1, overflow 1 → both today, second `overflow`.
10. Overdue task (due yesterday, Low, not focused) next to a Normal task, capacity 1 → Normal today, the overdue one tomorrow with `reason = priority`, not `atRisk`; in `focus` with `overdueDays = 1`, `focused = false`, `plannedDate` tomorrow. Overdue Low behind two High tasks → placed after them, nothing forced, `atRiskTaskIds` empty. Due date moved to tomorrow → out of `focus` and forced tomorrow.
11. Task due on a rest day → forced on the previous working day.
12. Pinned task takes its slot first; pinned in the past → today.
13. Pinned tasks on future days reduce `avail` for forcing.
14. `completedTodayCount = 1`, capacity 1 → no new priority picks today, forced tasks still appear. `countCompletedToday` counts only `completedOnPlan` tasks: capacity 2, six plain tasks; the fourth (tomorrow's) done with `onPlan: false` → today keeps its two tasks and the later days move up; the first done with `onPlan: true` → today shows one task, nothing is pulled in (D19).
15. Focus: 5 focused tasks → all 5 in `focus` in (priority, due, focusedAt) order and all still planned on their days in pool order; a focused task with a due date keeps its forcing and boost. `visibleFocus` skips the one on today's list and shows the next three; `hiddenFocusCount` = 1. Completing one (removing it from input) → order of the rest preserved.
15b. Mixed Focus: focused Normal task + overdue Low task + overdue High task → order High (overdue), Normal (focused), Low (overdue): priority wins, overdue leads only within equal priority. In the plan the same tasks follow pool order (priority, then age).
15c. A focused task on today's list (due today, or a pin in the past) is in `focus` but not in `visibleFocus`. A focused or overdue task beyond the horizon has `plannedDate = null` and is in the strip.
16. Boost clamps at 1 (Someday due tomorrow on scale 5 → effPriority 3; High due tomorrow → 1).
17. Horizon 7, 20 tasks, capacity 1 → 7 scheduled, 13 in `later`.
18. Determinism: same input twice → identical plan.
19. Performance: 500 tasks, horizon 90 → under 50 ms.
20. Deadline refill (D16): capacity 2, overflow 1, five tasks due today → 3 today, 2 `atRisk`. One completed (`completedTodayCount = 1`, four left) → still 3 today, 1 `atRisk`. Plain tasks in the same setup: one completed → 1 today, no refill.
21. Same with overflow 0 → 2 today, 3 `atRisk`; one completed → 2 today, 2 `atRisk`.

## Complexity
Per day: forcing is O(T log T) due to sorting; `avail` prefix sums are precomputed once per plan. Effective priority depends on `d`, so the pool is re-sorted per day (T log T). Total O(H × T log T) with H = horizon days. For H = 90, T = 500 this is trivially fast on a phone.

## Known limitations / future
- Capacity is a task count; effort estimates (points) would change `place()` to subtract weight. Keep the interface open.
- Pure EDF forcing can place a forced task on a day where a slightly higher-priority due task would have been the nicer choice; both deadlines are still met, so this is accepted.
- `notBefore` (snooze) is a simple filter in the pool (`d >= notBefore`), planned for a later milestone.
- Boost thresholds are global; per-task "lead time" could come later.
