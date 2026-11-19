---
tags: [archive, history]
created: 2026-11-20
---
# History (archive)

A compressed record of what was built, milestone by milestone, made on 2026-11-20 from the backlog, the retros of [[05 Roadmap]], the status log of [[Home]] and the device test of M3. Read it only for "why is it like this" questions; the current rules live in 01–04. The full texts (task notes, demos, findings) are in the git history of `docs/` before the 2026-11-20 cleanup, e.g. `git log -- "docs/06 Task Backlog.md"`. Lessons for the toolchain and tests moved to "Gotchas" in [[02 Architecture]].

| Milestone | Built | Release | Tests | Outcome |
|-----------|-------|---------|-------|---------|
| Planning | 2026-11-12 … 13 | — | — | Brainstorm, architecture, data model, planner design, backlog; D1–D16 |
| M0 Environment | 2026-11-13 | — | — | Toolchain, skeleton with strict lints and codegen, Android + Windows + web, CI + GitHub Pages |
| M1 Domain core | 2026-11-13 | — | 208 | `LocalDate`, `Task`, `Settings`, `Plan`, `Planner`; scenarios 1–21; then Focus (D17–D19, T-111) |
| M2 Data layer | 2026-11-13 | — | 302 | drift schema 1, repositories, device settings, providers to `planProvider`, day rollover, web storage |
| M3 MVP UI | 2026-11-14 | 0.2.2+3 | 460 | Today, Tasks, editor, Settings, Done list; device walkthrough on the emulator (closed after M4) |
| M4 Plan control | 2026-11-14 | 0.2.0 | 414 | Plan screen, pins, day overrides, at-risk ways out, Trash, scale migration |
| M5 Polish & release | 2026-11-14 | 0.3.0+4 | 476 | Morning notification, backup, icon and splash, integration test, signed release, user guide |
| T-601 Widget | 2026-11-15 | 0.3.1+5 | 485 | Home-screen widget with today's tasks |
| M7 Recurring tasks | 2026-11-15 … 16 | 0.4.0+6 … 0.5.3+11 | 602 → 721 | Repeat rules, one stored instance per series, ghosts, release dates; schema 3 |
| M9 Redesign | 2026-11-15 … 16 | 0.5.0+7, 0.5.4+12 | 693 → 732 | Theme tokens, task card with Done, done tasks stay in sight; schema 4 |
| M8 Task size | 2026-11-16 | 0.6.0+13 | 784 | Small / normal / large in half-slots, first fit; schema 5 |
| M10 Allowed days | 2026-11-16 … 17 | 0.7.0+14 | 852 | Tasks limited to some weekdays; schema 6 |
| M11 Tuning | 2026-11-17 … 20 | 0.8.0+15, 0.8.1+16 | 873 → 888 | Swipe to pin, quick add to today and the editor, quiet card v2, notes on the card, editor order, widget dots |

M9 was planned after M8 but built before it (owner): M8 then had the new card from the start, so M9 is v0.5 and M8 v0.6. The numbers stay in the order the milestones were planned.

## Planning (2026-11-12 … 13)
Two owner reviews closed every open question: D10 (deadlines spread: forcing + urgency boost), D11 (the Today flag queue, later replaced), D12 (sync-ready rows), D13 (uk/en, light/dark), D14 (Trash, no archive status), D15 (day start hour), overflow +1/+2/+3 as a setting, D16 (deadline slots refill, at-risk shown on Today). Superseded ideas are in [[Superseded decisions]].

## M0 — Environment & skeleton (2026-11-13)
T-001 toolchain, T-002 project, T-003 dependencies and codegen, T-004 skeleton and docs, T-005 CI and GitHub Pages, T-006 Windows and web targets. Decisions: develop on Windows and web first (ADR-10), `minSdk 24`, storage as an adapter, `json_serializable` deferred (ADR-8), `kotlin.incremental=false` (ADR-9).

## M1 — Domain core (2026-11-13)
T-101 `LocalDate`, T-102 `Task`, T-103 `Settings` and `CapacityResolver`, T-104 `Plan`, T-105 … T-109 planner (queue and priority fill, deadline forcing, overflow and at-risk, urgency boost, pins and completed today), T-110 performance (500 tasks × 90 days in about 2 ms), T-111 Focus replaces the Today queue (D17–D19, ADR-12). Changed: D16; priority colours as ARGB ints (ADR-11); the horizon counts today; pins honoured on rest days; worked example 1 corrected.

## M2 — Data layer (2026-11-13)
T-201 drift schema 1, T-202 `TaskRepository`, T-203 settings, day overrides and device settings, T-204 providers and `planProvider` (no debounce, ADR-13), T-205 `todayProvider` with a day-start timer, T-206 SQLite wasm for the web (IndexedDB survives a reload). Every write takes `now` from `clockProvider`; `DeviceSettings` has its own enums.

## M3 — MVP UI (2026-11-14) and M4 — Plan control (2026-11-14)
M3: T-301 app shell, l10n and themes (ADR-14), T-302 Today, T-303 editor (pin date moved in), T-304 Tasks, T-305 Settings, T-306 Done list, T-307 quick add, T-308 device walkthrough. M4, built before the walkthrough: T-401 Plan screen, T-402 pin from the Plan, T-403 day overrides, T-404 at-risk ways out, T-405 Trash with a 30-day purge, T-406 priority remap (removed again by ADR-17).

First release 0.2.0 with backup (T-502, ADR-16) and release signing (T-505, ADR-15); save → uninstall → install → restore passed on the emulator. Fixes from the phone in 0.2.1: snack bars that never hid, look-alike Trash buttons.

The device walkthrough (checklist "07 Device Test M3", emulator `TasksOrder_API36`, the clock moved to 23:59 for midnight and overdue) found: a scale round trip 5 → 10 → 5 raised every task (→ ADR-17: fixed levels of a ten-level table, schema 2, backup format 2); the Today header and the overload banner used different capacities; the system navigation bar stayed light in the dark theme (→ T-503); a rest day read "0/0" in the Plan. Fixed in 0.2.2. The owner checked the web build, vibration and light/dark on the phone. Known gap kept: no "discard changes?" when leaving the editor.

## M5 — Polish & release (2026-11-14)
T-501 morning notification (ADR-20: seven single notifications scheduled from the plan, no background job), T-502 backup / restore, T-503 icon, splash, navigation bar per theme, string review (ADR-21), T-504 integration test, T-505 release 0.3.0+4, T-506 user guide and changelog. `flutter_local_notifications` held at 22.x for `compileSdk 36`.

## T-601 — Home-screen widget (2026-11-15, 0.3.1)
A cache of the next seven plan days over the method channel `tasks_order/home_widget`, no `home_widget` package (ADR-22); Ukrainian user guide.

## M7 — Recurring tasks (2026-11-15 … 16)
Designed 2026-11-14 (D20, ADR-18). T-701 `Recurrence` and date math, T-702 series fields and `Task.successor`, T-703 release dates in the planner, T-704 ghosts, T-705 schema 3, T-706 backup format 3, T-707 the Repeat sheet, T-708 ghosts in the lists and a "Recurring" filter, T-709 walkthrough. From the owner's use: T-710 one completion a day for a series from completion, T-711 "Skip" in the menu (it was hidden behind Delete). Follow-ups in 0.5.1 … 0.5.3: T-712 a rule from completion has no ghosts (ADR-24, rewritten by the owner from "fix the skip date"), T-713 only the last completion of a series can be taken back, one active rule per series, T-714 "Not before" in the editor (a pin may be before it; the pin leads).

Changed: `Recurrence` is a plain sealed class, not `freezed`, so a broken rule is refused in release builds too; the successor id is a UUID v5 of `next/<id>`; an editor save re-anchors only for a new rule or new dates; restoring a skip removes its untouched successor. Bugs found on the emulator, not by tests: the Tasks list took the day of the last ghost; ghosts of a series piled up on one free day (a series became a chain, a ghost without dates expires); a returned copy with a rule reused its old successor id and overwrote the next repeat (now stored as a new task).

## M9 — Redesign (2026-11-15 … 16)
Designed 2026-11-15 from the owner's mockups (D22, ADR-23; package in `docs/design/redesign-2026-11/`). T-901 theme tokens with derived priority shades and a contrast test, T-902 shared task card, T-903 Today, T-904 Plan, T-905 Tasks, T-906 walkthrough, T-907 a done task stays on its plan day (schema 4, backup format 4). Follow-ups in 0.5.4: T-908 the task menu closes on a tab change, T-909 "Postpone until…" and "Pin to a day…", T-910 Today's empty states as a card, T-911 "Pinned to <date>", T-912 the add button on the Plan.

Changed: the mockups are a reference, not a contract (priority colours stay the app's, no due times, progress counts today's list, the Focus counter counts Focus, "Completed <day>" on a done card). Found on the emulator: lists ran under the status bar without an app bar (fixed with `TabBody`).

## M8 — Task size (2026-11-16)
Designed 2026-11-14 (D21, ADR-19). T-801 `Task.weight` and `TaskSize`, T-802 weighted capacity and first fit (`waitsForRoom`), T-803 weighted forcing and the top-level overflow, T-804 schema 5 and backup format 5, T-805 Size in the editor, chip, slots in the Plan and the overload banner, T-806 walkthrough.

Changed: `PlannedDay.capacityWeight` (today's room is odd after a small task); `effWeight` is 2 when every weekday is a rest day; every skipped task gets `waitsForRoom`; Today's progress still counts tasks; an unknown weight reads as the larger size on a tie. Performance: sorting the pool every day broke the 50 ms budget with 20 daily series; it is sorted only when needed. Open need noted: a Critical large task added during the day pushes today's shown tasks to tomorrow.

## M10 — Allowed days (2026-11-16 … 17)
Designed 2026-11-16 (D23, ADR-25). T-1001 `Task.allowedWeekdays`, T-1002 placement on allowed days, T-1003 forcing counts only the allowed days, T-1004 schema 6 and backup format 6, T-1005 the "Days" row and chip, T-1006 walkthrough.

Changed: `effWeight` of a task with a set is capped by the biggest weekday of the set; a forcing check also asks whether the task may be placed today; with a pin the editor shows only the pin hint. Accepted: an overdue task with a set is planned by priority and may land weeks later; a pin in the past keeps its old date on the card.

## M11 — Tuning (2026-11-17 … 20)
UI only, no planner, schema or backup change. T-1101 the right swipe on Tasks pins a task to its planned day (completion only by the Done button), T-1102 quick add: a "Today" chip and the full editor with what was typed (`TaskDraft`), T-1103 card v2 "quiet card" from the owner's `CARD_SPEC.md`, T-1104 walkthrough (0.8.0+15). Follow-ups in 0.8.1+16: T-1105 notes on the card and the ghost card (expandable block), T-1106 editor order (title, notes, priority, size, Focus, pin, Not before, due date, Days, Repeat) and small hints, plus the last editor row cleared of the system navigation, T-1107 coloured priority dots in the widget (cache format 2).

Changed: the quiet priority dot uses the level's colour, not the spec's five fixed colours; the pin chip keeps its date where no planned chip is; Catastrophic and Critical are levels 1 and 2 on every scale. Seen, not changed: an empty band in the quick-add sheet between the handle and the editor button.
