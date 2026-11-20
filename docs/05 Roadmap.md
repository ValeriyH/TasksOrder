---
tags: [roadmap, planning]
created: 2026-11-12
---
# 05 Roadmap

Each milestone ends with a walkthrough on the emulator (the phone gets releases in batches) and a short retro: new needs go to [[01 Brainstorm]] and the parking lot of [[06 Task Backlog]].

| Milestone | Version | Outcome |
|-----------|---------|---------|
| M0 — Environment & skeleton | — | Toolchain, project, CI, GitHub Pages |
| M1 — Domain core | — | `Planner` with forcing, overflow, urgency boost, pins, Focus |
| M2 — Data layer | — | drift, repositories, `planProvider`, day rollover, web storage |
| M3 — MVP UI | 0.1 … 0.2.2 | Today, Tasks, editor, Settings, Done list |
| M4 — Plan control | 0.2 | Plan screen, pins, day overrides, at-risk, Trash |
| M5 — Polish & release | 0.3 | Notification, backup, branding, signed release |
| M7 — Recurring tasks | 0.4, 0.5.1 … 0.5.3 | Repeat rules, series, ghosts (D20) |
| M9 — Redesign | 0.5 | Theme tokens, task card, done tasks in sight (D22) |
| M8 — Task size | 0.6 | Small / normal / large (D21) |
| M10 — Allowed days | 0.7 | Tasks limited to some weekdays (D23) |
| M11 — Tuning | 0.8.0, 0.8.1 | Swipe to pin, quick add options, quiet card, notes on the card, widget dots |
| M12 — Turns by waiting | 0.9 | Planned: a waiting task rises a level a day, an undone one gives way (D24) |

Current release: **0.8.1+16** (2026-11-20). Next: M12 (tasks in [[06 Task Backlog]]). What each milestone built, and why, is in [[History]].

## Cycle
1. Plan the milestone with the owner (decisions D… in [[01 Brainstorm]], ADRs in [[02 Architecture]]), split it into tasks in [[06 Task Backlog]].
2. Per task: test first for domain and data code; implement; `dart format lib test`, `flutter analyze`, `flutter test` clean; tick the task with its notes line.
3. At the milestone end: walkthrough on the emulator (release APK over the previous one, light and dark, uk and en), both user guides, [[09 Changelog]], version in `pubspec.yaml`, status in [[Home]].
4. Close the milestone: summary to [[History]], lessons to "Gotchas" in [[02 Architecture]], ideas to the parking lot; the backlog keeps only open work.

## Risks
- **Planner edge cases**: the test table of [[04 Planner Algorithm]] is the contract; every bug found in the UI becomes a new row before it is fixed.
- **Scope creep**: ideas go to the parking lot first.
- **Emulator vs. tests**: several bugs (ghost piles, a reused successor id, lists under the status bar) were found only on the emulator; keep the walkthrough.
