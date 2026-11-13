---
tags: [moc, tasksorder]
---
# TasksOrder — Project Home

Android app (Flutter) that takes an unsorted dump of tasks with priorities and optional due dates, and turns it into a realistic day-by-day plan driven by a configurable daily capacity.

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
