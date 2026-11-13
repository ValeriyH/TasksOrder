---
tags: [algorithm, planner]
created: 2026-11-12
updated: 2026-11-12
---
# 04 Planner Algorithm

The planner is a **pure function**: same inputs → same plan. No randomness, no clock access (today is an input).

```
Plan plan({
  required List<Task> activeTasks,
  required Settings settings,
  required Map<LocalDate, DayOverride> overrides,
  required LocalDate today,
  int completedTodayCount = 0,   // planned (non-flagged) tasks completed today
})
```

## Three kinds of tasks
| Kind | Who | Behaviour |
|------|-----|-----------|
| **Today queue** | `isToday == true` **or** `dueDate < today` (overdue, D7) | Outside capacity, not placed on any day, ignored by deadline math (D11). Queue order: priority, then `dueDate` (nulls last; overdue therefore first within a priority), then `todayFlaggedAt`. UI shows the first `todayVisibleLimit` (3); the queue refills as tasks are completed. An overdue task leaves the queue only when done or when its due date is moved to today or later / cleared. |
| **Due-dated** | `dueDate >= today` | Compete by *effective* priority (urgency boost, D10) and are **forced** when the deadline would otherwise be missed. |
| **Plain** | no due date | Compete by priority only. Never forced. |

Priority 1 ("Critical") is an ordinary level: it wins the priority fill but waits for a slot like everything else unless the user flags it Today.

## Inputs and derived values
- `capacity(d)` = `overrides[d]?.capacity ?? settings.weeklyCapacity[d.weekday]`. For `today`, subtract `completedTodayCount` (floor 0) so Today stays stable after ticking tasks (D3).
- Rest days never receive tasks (D6). `hardLimit(d)` = `baseCapacity(d) == 0 ? 0 : baseCapacity(d) + settings.maxOverflowPerDay`, where `baseCapacity` is the value **before** `completedTodayCount` is subtracted. So `completedTodayCount` only limits the priority fill; deadline-forced tasks keep refilling up to the hard limit (D16): capacity 2, overflow 1, five tasks due today → three shown, and each completion pulls in the next one.
- `effDue(t)` = `t.dueDate` — overdue tasks never reach the pool (they are in the Today queue, D7), so no clamping is needed; a task due *today* is simply forced today.
- `effPriority(t, d)` — urgency boost (D10):
  ```
  if t.dueDate == null: return t.priority
  slack = effDue(t) - d                      // days
  boost = slack <= settings.urgencyNearDays ? 2      // default 2
        : slack <= settings.urgencySoonDays ? 1      // default 7
        : 0
  return max(1, t.priority - boost)
  ```
- Pool ordering (used whenever "next by priority" is needed), evaluated for the day `d` being filled:
  1. `effPriority(t, d)` ascending (1 first)
  2. original `priority` ascending — a boosted task joins a tier but does not overtake that tier's originals
  3. `effDue` ascending, `null` last
  4. `createdAt` ascending

## Day loop
```
todayQueue = activeTasks where isToday or dueDate < today,
             sorted by (priority, dueDate nulls last, todayFlaggedAt)
             -> TodayEntry(taskId, flagged: isToday, overdueDays: max(0, today - dueDate))
pool       = activeTasks - todayQueue

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
```
`place()` removes the task from the pool and appends an entry. An entry gets `atRisk = true` when `d > effDue(t)`.

## Deadline forcing — `forcedToday(pool, d)`
Unit-size tasks with per-day capacities: *earliest deadline first* is optimal for feasibility, so the minimum number of due-dated tasks that must be done on `d` can be computed directly.

```
dueTasks = pool where dueDate != null, sorted by (effDue asc, priority asc, createdAt asc)
if dueTasks empty: return []

forcedCount = 0
for each distinct D in effDue values (ascending):
    need(D)  = count of dueTasks with effDue <= D
    avail(D) = sum over x in (d+1 .. D) of max(0, capacity(x) - pinnedOn(x))
    forcedCount = max(forcedCount, need(D) - avail(D))

return first forcedCount tasks of dueTasks   (EDF order)
```
- `avail` uses **base** capacity, not overflow: overflow is a last resort, so the planner is pessimistic about the future and may force a task a day early rather than rely on overflow later. This is intentional and is what spreads a cluster of deadlines over the preceding days.
- Plain tasks are never forced; they only fill leftover slots by priority.
- Because today's priority fill only consumes today's slots (which `avail` never counted), it cannot break future feasibility.
- Today-flagged tasks are not in `pool`, so they neither consume `avail` nor get forced. A flagged task with a due date is the user's responsibility; the UI still shows its due badge.

## Why two mechanisms (hard forcing + soft boost)
Forcing alone meets deadlines but is *lazy*: with comfortable capacity it leaves due tasks to the last feasible day, so the user experiences "the deadline came and everything is due at once". The boost makes due tasks win slots early when capacity allows; forcing is the safety net when it does not.

## Flags and reasons (what the UI shows)
| Flag | Meaning | UI |
|------|---------|----|
| Today queue | user-flagged or overdue, outside capacity | "Today" section on top; 3 visible, "+N more" counter, refills on completion; overdue entries get a red "overdue by N days" badge and actions *move due date / clear due date* |
| `reason = priority` | normal pick | no badge |
| `reason = deadline` | placed because of a due date, possibly pushing a higher priority later | badge "due" |
| `reason = pinned` | user fixed the date | badge "pinned" |
| `overflow` | above the day's capacity | day banner "1 extra because of deadlines" |
| `atRisk` | placed after its due date (impossible with current capacity) | red badge + Plan header "N tasks at risk"; Today screen banner "N tasks will not make their deadline" opening the list (`Plan.hasAtRisk`, D16) |

## Worked example 1 — priority vs deadline (tight capacity)
Settings: scale 5, capacity Mon–Fri 1, Sat 3, Sun 0, overflow 1, boost thresholds 7 / 2. Today = Mon 2026-11-16.

| Task | Priority | Due |
|------|----------|-----|
| K | 3 (Normal), **Today flag** | – |
| A | 2 (High) | – |
| F | 2 (High) | – (created after A) |
| B | 3 (Normal) | – |
| E | 3 (Normal) | Sat 21 |
| C | 4 (Low) | Tue 17 |
| D | 5 (Someday) | Wed 18 |

Result:
| Day | Tasks | Why |
|-----|-------|-----|
| Mon 16 | **K** (Today queue, outside capacity) + A | forced = 0 (C fits Tue, D fits Wed, E fits by Sat). C is boosted to tier 2 (slack 1) but A, F are originals of tier 2 → **A** by `createdAt`. K never enters the pool. |
| Tue 17 | C *(due)* | need(17)=1, avail=0 → forced. **F (High) is pushed by C (Low).** |
| Wed 18 | D *(due)* | need(18)=1, avail=0 → forced. |
| Thu 19 | E | E is due in 2 days → boost 2 → tier 1 (3 − 2), ahead of F (High, tier 2) |
| Fri 20 | F | priority |
| Sat 21 | B | priority; two Sat slots stay empty |
| Sun 22 | – | rest day |

Without the boost (thresholds 0 / 0) only Thu and Fri swap: **F** on Thu by priority, **E** on Fri (same priority as B, but it has a due date). Forcing alone already spreads the deadlines here; the boost only decides who goes first among the tasks that are not forced. It matters more when there is spare capacity (example 2).

_Corrected 2026-11-13 (T-108): the first version of this table kept E in tier 2 on Thu/Fri, which contradicts the `effPriority` formula; the formula is the rule._

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
1. Empty pool → every day empty, `later` empty, `todayQueue` empty.
2. No due dates, capacity 1 → tasks in priority order, one per day, ties by `createdAt`.
3. Capacity per weekday respected; Sun 0 skipped.
4. DayOverride replaces weekday capacity for that date only.
5. Worked example 2 → boosted result (L on Tue); with thresholds 0/0 → forcing-only result (L on Wed).
6. Worked example 1 → exact day/task map (Thu E, Fri F); with thresholds 0/0 → Thu F, Fri E.
7. Worked example 3 → 2/1/1 spread; overflow flag on Q.
8. Worked example 3 with overflow 0 → S on Thu with `atRisk`, listed in `atRiskTaskIds`.
9. Two tasks due today, capacity 1, overflow 1 → both today, second `overflow`.
10. Overdue task (due yesterday, not flagged) → in `todayQueue` with `overdueDays = 1`, `flagged = false`, absent from every `PlannedDay`, capacity untouched. Due date moved to tomorrow → back in the pool and forced tomorrow.
11. Task due on a rest day → forced on the previous working day.
12. Pinned task takes its slot first; pinned in the past → today.
13. Pinned tasks on future days reduce `avail` for forcing.
14. `completedTodayCount = 1`, capacity 1 → no new priority picks today, forced tasks still appear.
15. Today queue: 5 flagged tasks → all 5 in `todayQueue` in (priority, due, flaggedAt) order, none in any `PlannedDay`, capacity untouched, flagged tasks excluded from `avail` and forcing. Completing one (removing it from input) → 4 remain, order preserved (refill is a UI consequence of `take(3)`).
15b. Mixed queue: flagged Normal task + overdue Low task + overdue High task → order High (overdue), Normal (flagged), Low (overdue): priority wins, overdue leads only within equal priority.
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
