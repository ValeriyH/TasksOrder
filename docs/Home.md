---
tags: [moc, tasksorder]
---
# TasksOrder — Project Home

Flutter app (Android first; Windows and web for development) that takes an unsorted dump of tasks with priorities and optional due dates, and turns it into a realistic day-by-day plan driven by a configurable daily capacity.

## Documents
- [[01 Brainstorm]] — problem, ideas, scope, key decisions, open questions
- [[02 Architecture]] — tech stack, layers, project structure, testing strategy
- [[03 Data Model]] — entities, persistence schema, derived plan model
- [[04 Planner Algorithm]] — the scheduling algorithm with worked examples and test cases
- [[05 Roadmap]] — milestones
- [[06 Task Backlog]] — concrete tasks with definition of done

## Development cycle
Plan → Split into tasks → Implement → Test & fix → Next step (new needs analysis or next task from [[06 Task Backlog]]).

## Status
- 2026-11-12: brainstorm, architecture, data model, planner design and backlog written. Flutter SDK not installed yet (see T-001).
- 2026-11-12 (later): owner review → decisions D10 (deadline spreading + urgency boost), D11, D12 (sync-ready rows) added; docs and backlog updated.
- 2026-11-13: second review → D11 replaced by the **Today flag queue** (3 visible, refills), D13 bilingual uk/en + light/dark, D14 trash instead of archive, D15 configurable day start; overflow +1/+2/+3 as a setting. All open questions closed. Planning session complete; implementation (M0) starts in a later session.
- 2026-11-13 (later): D7 revised — overdue tasks automatically join the Today queue (outside capacity, sorted by priority) instead of being forced into planned slots. Priority labels for all scales fixed (uk + en).
- 2026-11-13 (M0 closed): toolchain installed, project skeleton with strict lints and codegen, targets Android + Windows + web, CI with GitHub Pages deploy (https://valeriyh.github.io/TasksOrder/). Decisions ADR-8 … ADR-10, `minSdk 24`. See the M0 retro in [[05 Roadmap]]. Next: M1, T-101 `LocalDate`.
- 2026-11-13 (M1 closed): domain core done and proven by 208 tests: `LocalDate`, `Task`, `Settings`, `Plan`, `Planner` (Today queue, deadline forcing, bounded overflow, at-risk, urgency boost, pins). New decision D16 (deadline slots refill, unachievable plan highlighted), ADR-11. See the M1 retro in [[05 Roadmap]]. Next: M2, T-201 drift schema.
- 2026-11-13 (brainstorm after M1): the Today flag and its queue are replaced by **Focus** (D17): a mark and a view, the task stays in the plan. Overdue tasks return to the pool as tasks without a date and stay in Focus (D18). Only completions from today's list use up today's capacity (D19). Pin date moves into the editor (T-303). ADR-12. T-111 done the same day (domain, tests, docs 02/03/04): 220 tests. Next: M2, T-201 drift schema.
- 2026-11-13 (M2 done): data layer complete: drift schema v1, repositories, device settings, providers up to `planProvider`, `todayProvider` that rolls the day over at `dayStartHour`, web storage (SQLite wasm, IndexedDB on GitHub Pages); 302 tests. ADR-13. See the M2 retro in [[05 Roadmap]]. Next: M3, T-301 app shell.
- 2026-11-14 (M3 and M4 UI done): all screens are in place: Today with Focus and quick add, Plan, Tasks with filters and the Done list, the task editor, Settings, Trash; uk/en, light/dark; 414 tests. Not done: the device walkthrough (T-308, [[07 Device Test M3]]), postponed until the app is in everyday use. See the M4 retro in [[05 Roadmap]]. Next: T-308, then M5.
- 2026-11-14 (first release build): backup and restore to a JSON file (T-502) and a signed release APK, version 0.2.0 (T-505, ADR-15, ADR-16); 443 tests. The release build passed save → uninstall → install → restore on the emulator. Next: install on a phone, then the home-screen widget (T-601).
