---
tags: [algorithm, planner]
created: 2026-11-12
updated: 2026-11-14
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

Priority 1 ("Critical") is an ordinary level: it wins the priority fill but waits for a slot like everything else. "Do it on this day whatever the capacity" is a pin. (One exception, D21: a large task of level 1 or 2 that does not fit a day, see "Task size".)

## Release dates: `notBefore` (T-703)
`release(t)` = `t.notBefore`, or today when it is empty or in the past. A task is **released** on the day `d` when `release(t) <= d`.
- The priority fill of `d` takes released tasks only.
- A pin beats it: a pinned task sits on its day whatever `notBefore` says.
- Deadline forcing can only pull released tasks into `d`, but it counts the unreleased ones too: they will need slots before their due dates (see the forcing section).
- A task released after the end of the horizon is in `later`. A task whose `notBefore` is later than its due date is placed from its release on and is at risk.
- Focus does not look at it: a focused task that is not released yet is in the strip with the day it is planned for.

The app sets `notBefore` for the next instance of a recurring task (D20); there is no field to set it by hand yet.

## Recurring tasks: ghosts (D20, T-704)
The stored instance of a series is an ordinary task: the rules above and below apply to it as they are. In addition, for every active task `t` with a `recurrence` **by schedule** the planner adds its later repeats as **ghosts**, candidates that exist only inside this computation:

```
base  = max(today, t.occurrenceDate)
dates = the dates of the rule after base
ghosts = one per date, while date <= today + horizon - 1
```
A rule **from completion** has no ghosts (T-712, owner 2026-11-16): its dates depend on when each repeat is done, so ghosts would only be guesses that take places of the coming days. Its one stored instance is planned as any task; the next one appears when it is completed or skipped ([[03 Data Model]]).

A ghost has the priority of `t`, `createdAt` of `t` (ties between repeats of one series: earlier date first) and its dates follow the dates `t` has, like the successor in [[03 Data Model]]:

| `t` has | Ghost for the date `x` (previous repeat on `p`) |
|---------|--------------------------------------------------|
| a pin | pinned on `x`; reason `pinned`; with a due date on `t`, due at the same distance from the pin |
| a due date only | due on `x`, released on `p + 1`: it competes inside its own period, with boost and forcing |
| neither | released on `x`, then by priority |

- A ghost is never placed today: every ghost is released after `base`, which is today or later.
- **Order within a series** (found on the emulator, T-709): the stored task and its ghosts are a chain. A member may be placed on `d` only when every earlier member is placed on a day before `d` or has expired. So two repeats of a series never share a day and a ghost never comes before the task it repeats.
- **A ghost without dates expires** the day before the next date of the rule (`expiresOffset`): a missed repeat is dropped. A ghost that finds no day in its window is dropped, it does not wait. Without this, a "Mon, Tue, Thu, Sat" task made on a Sunday with full working days put three repeats on the Saturday. Pinned ghosts and due-only ghosts keep their own dates (and the at-risk flag) as before.
- A ghost takes a slot, lowers `avail` and can be forced like a real task: that is the point, the load of the coming weeks is real.
- Its entry is `PlanEntry(taskId: t.id, occurrenceDate: x)`. The UI shows it in the Plan without a checkbox; a tap opens `t`.
- Ghosts are not in `focus` and not in `laterTaskIds` (a ghost that found no day inside the horizon is dropped). A ghost placed after its due date has `atRisk` on its entry but is not in `atRiskTaskIds`: the banner and the at-risk list are about tasks the user can act on.
- Repeats do not pile up: when `t` was missed, `t` itself is the overdue task (D18) and ghosts start after today.
- Cost: at most one ghost per day of the horizon for each series (a daily task and 90 days: 89).

## Task size: weights (D21; T-802, T-803)
The planner counts **half-slots** instead of tasks. The sections below this one still speak of tasks and slots: with every task normal (weight 2) the two read the same.

```
effWeight(t) = min(t.weight, 2 × max(settings.weeklyCapacity))   // small 1, normal 2, large 4
cap2(d)      = 2 × capacity(d)             // for today: minus completedTodayWeight, floor 0
hard2(d)     = 2 × hardLimit(d)            // 0 on a rest day
load(day)    = sum of effWeight over its entries
```
- **The cap** uses the weekly template, not the day overrides: one holiday must not change the weight of every large task. With 1 on every weekday a large task weighs 2 half-slots, the same as a normal one, so every task fits some working day. A week of rest days only (capacity from day overrides alone) caps at 2, so no task weighs 0 (T-802). `Planner.effWeight(task, settings)`.
- **`completedTodayWeight`** replaces `completedTodayCount`: the sum of `effWeight` of the tasks completed today with `completedOnPlan == true` (D3, D19), `Planner.completedTodayWeightOf`. A small task done from today's list leaves half a slot used, not a whole one. `countCompletedToday` stays for the "done of total" of the UI.
- **Pins** are placed whatever the weight, as now; their weight is in the load and in `pinnedOn(x)`.
- **Priority fill is first fit in pool order**:
  ```
  for t in pool in order for d, released tasks only:
      if load(day) >= cap2(d): break
      if load(day) + effWeight(t) <= cap2(d): place(t, reason: priority)
      else: t.waitsForRoom = true            // skipped only because of its weight
  ```
  A large task therefore lands on the first day that still has two free slots when its turn comes, and lighter tasks behind it take the days it could not use. Queue `1, ½, 1, 1, ½` with capacity 1 → day 1: `1`; day 2: `½ + ½`; day 3: `1`; day 4: `1`. Every task the fill reaches and skips for its weight gets `waitsForRoom`, so there both normal tasks of day 2 have it (scenario 35).
- **Top-level overflow** (the only case where priority alone passes the capacity). Before the fill of `d`:
  ```
  t = first released task of the pool for d
  if t.priority <= 2                          // own level: Catastrophic, Critical; not effPriority
     and effWeight(t) > 2 × baseCapacity(d)   // does not fit the day at all
     and completedTodayWeight + load(day) + effWeight(t) <= hard2(d):
      place(t, reason: priority)              // gets the overflow flag as any entry above capacity
  ```
  At most one such task a day, and never on a rest day (`hard2 = 0`). With the three sizes this is a large task on a day of capacity 1 with overflow ≥ 1. A top-level task that fits the day needs no rule: it is first in the fill. "First" skips the tasks that are not released or not ready in their series (they cannot be placed on `d` anyway). The check runs only on a day smaller than the heaviest task of the pool, so a plan of normal tasks does not pay for it.
- **Forcing** sums weights:
  ```
  need(D)      = sum of effWeight over dueTasks with effDue <= D
  avail(D)     = sum over x in (d+1 .. D) of max(0, 2 × capacity(x) - pinnedWeightOn(x))
  forcedWeight = max over D of need(D) - avail(D)
  take dueTasks in EDF order until the weight taken >= forcedWeight;
  a task that would pass hard2(d) is skipped and the next one is tried
  ```
  With unit weights this is the formula of the forcing section.
- **A heavy task counts only the days it fits** (owner, 2026-11-14). The sum above would count the free half-slots of days that are too small for a large task, so the check is repeated for every weight `w` above normal that the due tasks have (with the three sizes: for the large ones):
  ```
  free(x)       = max(0, 2 × capacity(x) - pinnedWeightOn(x))
  need_w(D)     = sum of effWeight over dueTasks with effWeight >= w and effDue <= D
  avail_w(D)    = sum of free(x) over x in (d+1 .. D) with free(x) >= w
  forcedWeight_w = max over D of need_w(D) - avail_w(D)
  take the dueTasks with effWeight >= w in EDF order until the weight taken >= forcedWeight_w,
  under the same hard2(d) limit
  ```
  The forced set of `d` is the union of the two checks, placed in EDF order. In the code (`Planner._force`) it is one pass over the due tasks in EDF order: a task is taken while a check it belongs to still needs weight and it fits (released, ready, inside `hard2`); what it weighs is taken off every check it belongs to, since a task done today needs no room later. Like the check without weights, each check is cut to the released weight due by `D` (T-703). Like the rest of forcing this is pessimistic about overflow later: a large task due on Wednesday with no big day before it is forced on the first working day that can take it with overflow, not left for Wednesday; with a free Saturday before its date it is not forced until that Saturday.
- Forcing with mixed weights stays a **heuristic**: packing whole tasks into days is bin packing, and `avail_w` does not know what the lighter tasks will take from the big days. The planner may force a task a day early, or find out late that a task has no day before its date; what is left is at risk, shown as now.
- **Ghosts** (D20) carry the weight of their task.
- The trim at the end of a day works on the load: entries are returned to the pool from the tail while `load(day) > hard2(d)`; pinned entries are never trimmed.

## Allowed days (D23, ADR-25; T-1002, T-1003)
A task may carry a set of weekdays, `allowedWeekdays`; without it every day is allowed.

```
allowed(t, d) = t.allowedWeekdays == null or d.weekday in t.allowedWeekdays
```
It is one more "may `t` be placed on `d`" test, next to the release date (T-703) and the order of a series (T-709). Everything else about the task is as for any task.

- **Priority fill, top-level overflow, forced picks** of `d` skip a task with `allowed(t, d) == false`. Such a skip does not set `waitsForRoom` (the day had room, it was the wrong day), and "the first task of the queue" of the top-level overflow passes over it as over a task that is not released.
- **No extra state for a miss.** A task not done on its day is planned again from the new today and lands on the next allowed day with room. It is not in `focus` and not at risk for that.
- **A rest day stays empty** (D6): an allowed day with capacity 0 (weekday or override) is passed over. A task whose allowed days never have room inside the horizon is in `later`.
- **A pin wins**: a pinned task sits on its day whatever the set says. A pin in the past, which means today for other tasks, means the first day `>= today` with `allowed(t, d)` (today itself when it is allowed); the task is placed there as pinned, whatever the capacity. `pinnedOn(x)` counts it on that day.
- **Urgency boost** is unchanged: the slack is counted in calendar days.
- **Overdue** (D18) is unchanged: the due date stops counting, the task is in `focus` and is planned by priority on its allowed days.
- **Ghosts** (D20) carry the set of their task; a pinned ghost stays on its date. A ghost without dates that meets no allowed day before it expires is dropped, as a ghost that finds no room.
- **Weight** (D21): `effWeight` of a task with a set is capped by the biggest weekday **of the set**, `min(t.weight, 2 × max(weeklyCapacity[x] for x in set))`, and by 2 when all of them are rest days. A large task "only Mon" with one slot on Mondays weighs one slot and takes a Monday; with the cap of the whole week it would fit none of its days and never be planned (T-1003).
- **At risk**: a task whose allowed days up to its due date cannot take it is placed on the first allowed day after the date and flagged, as any task that is late; it is visible from today.

### Forcing with allowed days (T-1003)
The plain check counts the free room of every day up to `D`, also of days the task cannot use. So, like the check per heavy weight of D21, the check is repeated for every distinct set `S` that the due tasks carry:

```
group(S)    = dueTasks with allowedWeekdays != null and allowedWeekdays ⊆ S   // can only use days of S
need_S(D)   = sum of effWeight over group(S) with effDue <= D
avail_S(D)  = sum of free(x) over x in (d+1 .. D) with x.weekday in S
pull_S(D)   = sum of effWeight over group(S) with effDue <= D, released on d and allowed(t, d)
forced_S    = max over D of min(need_S(D) - avail_S(D), pull_S(D))
take the tasks of group(S) in EDF order until the weight taken >= forced_S, under hard2(d)
```
- The forced set of `d` is the union of all checks (plain, per heavy weight, per set), placed in EDF order in the one pass of `Planner._force`; a task taken lowers every check it belongs to.
- The cut of every check (`released(D)` of T-703) also asks `allowed(t, d)`: only a task that may be placed on `d` frees room by being pulled into `d`. So in the plain check a cluster of tasks that cannot be done today forces the unrestricted ones due by the same date, not nothing.
- A group with heavy tasks gets the heavy check inside the set too: `need` over the tasks of `group(S)` with `effWeight >= w`, `avail` over the days of `S` with `free(x) >= w`.
- Result: "only Sat, due Mon 30" has `avail_S = 0` on Sat 28 and is forced there; on Sat 21 the room of Sat 28 still covers it, so it is not forced and competes by priority. When Sat 28 is a rest day by an override, it is forced on Sat 21.
- Still a heuristic, as with mixed weights: two different sets that overlap (`{Thu, Fri}` and `{Fri, Sat}`) are checked each on its own and by the plain check, not as a matching; what does not fit is at risk on its day.
- Cost: one more pass per distinct set among the due tasks (few in practice), with its own running totals in `_FutureCapacity`. A set whose weekdays are all rest days stops counting after the last override that gives one of them capacity, so "only Sun, due in ten years" does not walk the calendar.
- In the code: `_Candidate.dayMask` (the set as bits), `_ForceCheck` (a set, a minimum weight, the weight still to place), `_FutureCapacity.between(…, minFree:, mask:)`.

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
     + ghosts of the recurring tasks                   // D20, T-704

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
        place(pool.firstFor(d), reason: priority)     // released tasks only (T-703)

    // Flags
    for entry at index >= capacity(d): entry.overflow = true
    trim(day, hardLimit(d))        // tail goes back to the pool; it will be atRisk when placed after effDue

later = whatever remains in pool, without ghosts

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

### With release dates (T-703)
A task that is not released on `d` cannot be done on `d`, but it still needs a slot between its release and its due date, and that slot is no longer free for the others. So `need` counts every due-dated task, and the result is cut to what can be pulled into `d`:
```
need(D)     = count of dueTasks with effDue <= D                       // released or not
released(D) = count of dueTasks with effDue <= D and release <= d
forcedCount = max over D of min(need(D) - avail(D), released(D))

return first forcedCount released tasks of dueTasks   (EDF order)
```
Without unreleased tasks this is the formula above. The `min` keeps a tight cluster of unreleased tasks (three ghosts due in one week with one free slot) from forcing unrelated tasks with later deadlines into `d`: only tasks due by the same `D` free a slot there. What still does not fit is at risk on its day, as before.

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
| `waitsForRoom` (D21) | a lighter task went ahead because this one did not fit what was left of an earlier day | chip "Waits for a day with room" next to its planned day (Plan, Today, Tasks); the user can pin it or raise the capacity of a day |
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

With T-703 (release dates), in `test/domain/planner_test.dart`:

22. `notBefore` in three days, Critical, next to Low tasks, capacity 1 → the Low tasks take the first three days, the Critical one its release day. `notBefore` in the past or today → no effect.
23. A pin earlier than `notBefore` → placed on the pin. `notBefore` beyond the horizon → in `later`. Focused and not released → in `focus` with its `plannedDate`.
24. Forcing with an unreleased task: capacity 1; X due Thu and released Thu, Y due Thu and released today (Mon), a High task without a date → Y is not left for Thu (X needs that slot): `need(Thu) = 2`. Y is forced no later than Wed, X is on Thu, nothing at risk.
25. Two unreleased tasks due on the same day with one slot there, plus a released task with a later due date → the released one is not forced today (the `min`), one of the two is at risk.

With T-704 (ghosts), in `test/domain/planner_ghosts_test.dart`:

26. Weekly task without dates, `occurrenceDate` today, horizon 30 → the instance by priority from today, ghosts released on days 7, 14, 21, 28, each on its release day or the next free one; all with `occurrenceDate`, none in `later` or `focus`.
27. Monthly by schedule, anchor Jan 31, horizon 90 from Jan 31 → ghosts for Feb 28 (29 in a leap year), Mar 31, Apr 30.
28. Weekdays Mon/Wed/Fri with a pin → ghosts pinned on those days, also on a rest day and above the capacity; they lower `avail` for the forcing of other tasks.
29. Due-only weekly task → each ghost is due on its date and released the day after the previous one; three of them are never packed into the first week, even at the highest priority.
30. Missed instance (`occurrenceDate` three days ago, weekdays rule) → one real task, overdue and in `focus`; the first ghost is the first rule date after today.
31. From completion, every 10 days, instance not done yet → no ghosts, only the instance; its successor (done today) is planned from day 10, again without ghosts (T-712). 31b. A pinned rule from completion has no ghosts either; a weekly rule beside it keeps its own.
32. A ghost of a due-only task that cannot make its date → `atRisk` on the entry, `atRiskTaskIds` unchanged. A ghost that fits no day of the horizon → dropped.
33b. Repeats of a series do not pile up: "Mon, Tue, Thu, Sat" without dates made on a Monday, four older tasks on Mon..Thu → the task on Friday, one ghost on Saturday (Tue and Thu expired), never two of the series on a day; a daily due-only series keeps its members on increasing days.
33. Determinism and performance with ghosts: 500 tasks, 20 of them daily series, horizon 90 → same plan twice, under 50 ms.

With T-802 and T-803 (task size, D21), in `test/domain/planner_weight_test.dart`. Sizes: S = small (½), N = normal (1), L = large (2). Where a scenario says "capacity 1", the week is `[1,1,1,1,1,3,0]` starting on Monday unless it says "on every working day", so an L weighs two slots:

34. Every task normal → all earlier scenarios give the same plan.
35. Queue N, S, N, N, S by priority, capacity 1 → day 1: N; day 2: S + S; day 3: N; day 4: N. The second N has `waitsForRoom`.
36. A Normal-priority L first in the queue, six Low N behind it → Mon–Fri take five N, the L is first on Saturday with one N next to it; the L has `waitsForRoom`.
37. Capacity 1 on every working day → an L weighs one slot and takes the first day. A day override of 3 on one date does not change its weight.
38. Critical L first in the queue, capacity 1, overflow 1 → on the first day, alone, `overflow`; the next task on the day after.
39. The same with overflow 0 → the L waits for Saturday. The same with a High L (level 3) and overflow 1 → it waits for Saturday.
40. A Normal L with a due date that the boost raises to Critical → the rule does not apply (own priority); it is placed by the fill or by forcing.
41. A Catastrophic N ahead of a Critical L, capacity 1, overflow 1 → day 1: the N; day 2: the L with `overflow`.
42. Stable today: capacity 1, two S on today's list, one done on plan → today keeps the other S and nothing is pulled in. Capacity 1, the N of today done on plan, a Critical L next in the queue → the L is not placed today.
43. Today is Monday, L due Wednesday, capacity 1, overflow 1 → forced on Monday (no day before Wednesday fits it) with `overflow`, reason `deadline`, not at risk. With overflow 0 → at risk on Saturday, in `atRiskTaskIds`.
43b. Today is Monday, a Low L due next Monday, thresholds 0/0, five plain N of a higher priority → the N take Mon–Fri, the L is forced on Saturday (the only day before its date that fits it), not at risk. With Saturday filled by a pinned L → the L due next Monday is forced today with `overflow`.
44. Two S due today next to a plain Critical N, capacity 1 → the two S today (forced), the N tomorrow.
45. A pinned L on a day of capacity 1 → placed, the day is overloaded, nothing else is filled in; the forcing of other tasks sees no free room on that day.
46. Weekly L series → the instance and each ghost take two slots of a Saturday.
47. Determinism and performance with mixed weights: 500 tasks, a third of each size, horizon 90 → same plan twice, under 50 ms.

With T-1002 and T-1003 (allowed days, D23), in `test/domain/planner_days_test.dart`. Week `[1,1,1,1,1,3,0]`, today is Monday 2026-11-16 unless said otherwise:

48. No task has a set → every earlier scenario gives the same plan.
49. A Critical task "only Sat" next to five Low tasks → the Low tasks take Mon–Fri, the Critical one is on Saturday; not in `focus`, not at risk, no `waitsForRoom`.
50. A Low task "only Sat" and enough tasks of a higher priority to fill Mon–Sat → it is on the Saturday of the next week; with the horizon cut before that Saturday → in `later`.
51. "Only Sat" with a day override of 0 on this Saturday → the next Saturday. "Only Sun" (a rest day in the week) → `later`; with an override of 1 on one Sunday → on that Sunday.
52. Pins: "only Sat" pinned on Wednesday → on Wednesday, reason `pinned`. Pinned on the Wednesday of last week → on this Saturday, reason `pinned`, also when Saturday is full; when today is a Saturday → today.
53. "Thu, Fri" planned from a Friday that is full → the Thursday of the next week, not Saturday or Monday.
54. A weekly series by schedule without dates, anchored on Monday, "only Sat" → the instance and each ghost on the Saturday of its week, one a week. A pinned series keeps its pinned dates.
55. Forcing: a Low "only Sat" task due Mon 30 Nov, thresholds 0/0, enough plain tasks of a higher priority to fill both Saturdays → not on Sat 21, forced on Sat 28 (reason `deadline`), not at risk.
56. The same with an override of 0 on Sat 28 → forced on Sat 21.
57. Capacity 1 on every working day, overflow 0; two "Thu, Fri" tasks and one task without a set, all due Friday, plain tasks of a higher priority on the other days → the two take Thursday and Friday, the third is forced no later than Wednesday; nothing at risk.
58. "Only Sat" due Thursday → on Saturday with `atRisk`, in `atRiskTaskIds`.
59. An overdue "only Sat" task → in `focus` with its `plannedDate` on a Saturday, placed by priority, not at risk.
60. A large "only Sat" task due Mon 30 Nov, with pins on Sat 28 that leave one free slot there → the heavy check inside the set forces it on Sat 21 (the last Saturday that can hold it), not at risk. Determinism and performance: 500 tasks, a fifth with a set, horizon 90 → same plan twice, under 50 ms.

## Complexity
Per day: forcing is O(T log T) due to sorting; `avail` prefix sums are precomputed once per plan. Effective priority depends on `d`, so the pool is re-sorted per day (T log T). Total O(H × T log T) with H = horizon days. With heavy due tasks (D21) forcing runs once more per heavy weight, with its own running totals of the free room. For H = 90, T = 500 this is trivially fast on a phone.

## Known limitations / future
- Capacity is a weight since T-802 and forcing sums weights since T-803, see "Task size". Forcing with mixed weights is a heuristic, not an exact packing.
- A task is done within one day (D21): a job longer than the biggest day is split by hand; there is no grouping of the parts yet.
- Pure EDF forcing can place a forced task on a day where a slightly higher-priority due task would have been the nicer choice; both deadlines are still met, so this is accepted.
- `notBefore` is a release date (T-703). Set by hand in the editor since T-714 ("Not before").
- A rule from completion shows no repeats ahead (T-712), so its later load is not in the plan; a window "done within N days" is in the parking lot.
- The forcing formula with release dates checks the periods that start tomorrow. A cluster of unreleased tasks that cannot fit its own period is not solved earlier; it shows as at risk.
- Allowed days (D23): a low task with one allowed day a week can be passed over for weeks by tasks of a higher priority that could have gone elsewhere; accepted, as for any low task (parking lot: a share of the slots per priority level).
- Boost thresholds are global; per-task "lead time" could come later.
