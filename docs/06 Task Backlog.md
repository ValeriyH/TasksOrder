---
tags: [backlog, tasks]
created: 2026-11-12
---
# 06 Task Backlog

Format: `- [ ] **T-xxx Title** — what / definition of done. _depends:_ …`, grouped under the milestone (`## M12 — Name (v0.9)`). Task ids are `T-<milestone><nn>` (T-1201). A done task gets `[x]` and one `_Notes (date):_` line: what was built, where, tests, anything learned.

When a milestone is closed, its tasks leave this file: a short summary goes to [[History]] (tasks one line each, changed decisions), lessons for the toolchain and tests to "Gotchas" in [[02 Architecture]], new ideas to the parking lot below. Closed milestones M0–M11 (T-001 … T-1107) are summarised there.

## Open
Nothing scheduled; the next milestone is the owner's choice (parking lot or a new need).

## Parking lot (not scheduled)
Planner:
- A share of the slots per priority level against starvation of low tasks, "speculative push" (owner 2026-11-16, preliminary): something more important always exists, so a low task never gets its turn; e.g. of a run of slots High gets 10, Normal 5, Low 1. For all tasks; it would also cover a low task with one allowed day a week (D23). Needs its own brainstorm
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
