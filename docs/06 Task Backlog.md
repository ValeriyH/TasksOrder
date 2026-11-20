---
tags: [backlog, tasks]
created: 2026-11-12
---
# 06 Task Backlog

Format: `- [ ] **T-xxx Title** — what / definition of done. _depends:_ …`, grouped under the milestone (`## M12 — Name (v0.9)`). Task ids are `T-<milestone><nn>` (T-1201). A done task gets `[x]` and one `_Notes (date):_` line: what was built, where, tests, anything learned.

When a milestone is closed, its tasks leave this file: a short summary goes to [[History]] (tasks one line each, changed decisions), lessons for the toolchain and tests to "Gotchas" in [[02 Architecture]], new ideas to the parking lot below. Closed milestones M0–M11 (T-001 … T-1107) are summarised there.

## M12 — Turns by waiting (v0.9)
A waiting task rises one level a day and a task shown on today's list starts again from its own level (D24, ADR-26). Spec and test table: "Turns by waiting" in [[04 Planner Algorithm]] (scenarios 61–75).

- [ ] **T-1201 Planner: order by waiting** — `Task.waitingSince` in the domain (`LocalDate?`, null = today; copied by `copyWith`, not by the successor); the pool order of "Turns by waiting": level-1 tier, `score = effPriority − waited` without a floor, own level, `effDue`, age; ghosts and tasks with `notBefore` wait from their release; re-sort only when the boost changes (`score + d` is constant). Tests: scenarios 61–70 in `test/domain/planner_turns_test.dart`; the earlier planner tests stay green (61). The pool ordering bullet under "Inputs and derived values" is replaced by a reference to the new section.
- [ ] **T-1202 Data: schema 7 and backup 7** — `tasks.waiting_since TEXT` (nullable), `settings.aging_as_of TEXT`; the migration fills both with the local date of the upgrade for active tasks (a task does not start from `createdAt`, or every old task would jump to the top). Backup `waitingSince` (left out when null) and `agingAsOf`; version 7; versions ≤ 6 read with "waits since the restore day". New tasks get `waitingSince` = the day of creation (quick add, editor, successor of a series); edits keep it. Tests: `SchemaVerifier` 6 → 7, backup round trip and old versions, scenario 75. [[03 Data Model]] updated. _depends:_ T-1201
- [ ] **T-1203 Day rollover pass** — replay `agingAsOf .. today − 1` (`plan(today: Y)` with horizon 1, at most 366 days), set `waitingSince = Y + 1` for the stored tasks on each list, `agingAsOf = today`, one transaction; runs at start and when `todayProvider` changes; `planProvider`, the widget cache and the notifications wait for `agingAsOf == today`. Tests: scenarios 71–74 with a fake clock. "Day rollover" in the key flows of [[02 Architecture]] no longer says "no writes". _depends:_ T-1202
- [ ] **T-1204 Docs and release 0.9.0** — both user guides (why a Low task can come before a Critical one; Catastrophic never gives way; a pin is still the way to say "this day"), [[09 Changelog]], version, [[Home]] status; D24 / ADR-26 / the planner section lose "planned". Walkthrough on the emulator: move the clock over several days (`adb root`, `auto_time 0`) and check that a task left undone gives way and a Low one gets its day; release APK over 0.8.1, uk and en. _depends:_ T-1203

## Parking lot (not scheduled)
Planner:
- A Critical large task added during the day takes today and pushes the tasks already shown there to tomorrow (today's list is sticky only for completions, D3); the owner may want today's list kept as it is (M8 retro)
- Places with opening days shared by several tasks ("the office: Thu, Fri"), on top of the allowed days of D23
- Tags / projects, subtasks; grouping for the parts of a job split by hand (a task is done within one day, D21). Owner's suggestion: mark the tasks of a group with a tag; tasks of a group keep their own order, and the 2nd task of a group cannot be placed before the 1st

Recurring tasks:
- "Skip this time" for a ghost (a future repeat in the Plan); now only the stored instance can be skipped, so it needs a record of skipped dates in the series
- An end of a series (until a date / N times), "the Nth weekday of a month", a narrower window for a due-dated repeat ("show it only a week before")
- A window for a repeat from completion: "done within N days" after it becomes available, so a low-priority repeat is not put off for ever (owner 2026-11-16; how to count it is open, since the start of such a repeat is not known ahead)
- Complete on another day: "Done on…" with a date, for a task done earlier but ticked late; a repeat from completion then counts its next date from that day (owner 2026-11-16: had a haircut on the 12th, ticked on the 25th)

Screens:
- Search over all tasks, done ones included (owner 2026-11-15)
- Fewer tabs: Today as the focus of the day, Plan as the schedule that also takes over the Tasks list with its filters and Trash (owner 2026-11-15, to think over)
- A tap on a free slot in the Plan adds a task pinned to that day (D22 mockups)
- "+1 more" button on Today (pull the next task after completing, D3)
- "Discard changes?" when leaving the editor with unsaved changes
- The quick-add sheet has an empty band between the drag handle and the row with the editor button
- Home-screen widget in the style of D22
- Stats and streaks

Notifications:
- A notification per task: a task can have a time, and a push notification / sound comes when it is due

Sync:
- Sync between devices (a `SyncEngine` behind the existing repositories; last-write-wins on `updatedAt`, tombstones via `deletedAt`, D12)
- Family group: a partner sees my load (n/capacity per day), proposes tasks into my queue (`proposed` status, accept / decline), `ownerId` / `assigneeId`
