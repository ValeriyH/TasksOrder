---
tags: [moc, tasksorder]
---
# TasksOrder — Project Home

Flutter app (Android first; Windows and web for development) that takes an unsorted dump of tasks with priorities and optional due dates, and turns it into a realistic day-by-day plan driven by a configurable daily capacity.

## Documents
- [[01 Brainstorm]] — the product: problem, idea, features, decisions D1–D24, glossary
- [[02 Architecture]] — stack, layers, project structure, flows, testing, gotchas, ADRs
- [[03 Data Model]] — entities, persistence schema, derived plan, backup and widget formats
- [[04 Planner Algorithm]] — the scheduling algorithm with worked examples and its test table
- [[05 Roadmap]] — milestones and the development cycle
- [[06 Task Backlog]] — open tasks and the parking lot
- [[08 User Guide]] — how to use the app ([[08 User Guide uk|українською]])
- [[09 Changelog]] — what changed in each version
- `design/redesign-2026-11/` — the owner's design package (README there says what is current)
- `archive/` — [[History]] (what each milestone built) and [[Superseded decisions]]; read only when the history matters

## Status
- **2026-11-20, 0.8.1+16**: M0–M11 done (planner, data, all screens, recurring tasks, redesign, task size, allowed days, tuning; widget and morning notification). 888 tests. Docs cleaned up: closed work moved to `archive/`. Next: M12 — turns by waiting (D24), planned in [[06 Task Backlog]].
