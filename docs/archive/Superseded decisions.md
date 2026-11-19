---
tags: [archive, decisions]
created: 2026-11-20
---
# Superseded decisions (archive)

Decisions that were in force once and were replaced. The rules in force are D1–D23 in [[01 Brainstorm]] and the ADRs in [[02 Architecture]]. Full original texts: git history of `docs/` before the 2026-11-20 cleanup. See also [[History]].

- **"Critical tier"** (2026-11-12): the highest priority would go to today regardless of capacity. Replaced the same day by the Today queue (ADR-5), later by Focus and pins.
- **D11 — Today flag queue** (2026-11-12 … 13): any task could be flagged "Today"; flagged tasks left the plan, ignored capacity and deadline math, and formed a refilling queue on top of Today, three visible. Replaced by **D17 Focus** (2026-11-13): the queue lived for days and became a second backlog, and flagged tasks lost their deadline protection. Focus is a view; the task stays planned. "Do it today above the limit" is a pin.
- **ADR-5 — `Plan.todayQueue`** (2026-11-13): the Today queue as a planner output. Replaced by `Plan.focus` (ADR-12, T-111).
- **D7, overdue part** (2026-11-13): an overdue task joined the Today queue outside capacity. Replaced by **D18**: an overdue task is planned by priority like a task without a date and stays in Focus. The rest of D7 holds: unfinished planned tasks return to the pool at the day boundary.
- **Before D19**: every completion lowered today's capacity, so doing a later task ahead pushed a task out of today. Now only completions from today's list count.
- **D1, priority as the position in the scale** (2026-11-12 … 14): shown as "Label (n)", stored as 1..scale; a scale change remapped tasks (T-406: keep values when the scale grows, `ceil(p/2)` when it shrinks). The device test showed a 5 → 10 → 5 round trip raised every task. Replaced by **ADR-17**: a priority is a fixed level of a ten-level table, the scale only chooses the levels offered, the number is not shown; schema 2 and backup format 2 converted the old positions.
- **Priority colours, first version** (2026-11-12): amber for the ordinary level looked like a warning. Since 2026-11-13: red, orange, green (Normal), teal, blue by the position of a level in the scale.
- **Ghosts for a rule from completion** (D20 as designed, M7): they assumed every repeat is done on its day and took places of the coming days on guessed dates. Removed by **ADR-24** (T-712).
- **Swipe right on Tasks completes** (M3 … M10): since T-1101 it pins the task to its planned day; completion is only the Done button.
- **The redesign package's own card** (SPEC.md "TaskCard", M9): replaced by `CARD_SPEC.md`, the quiet card v2 (T-1103). Its five fixed priority colours were never taken.
- **`json_serializable` for backup** (ADR-8, M0): failed with freezed 4 and `build_runner` 2.17; backup uses hand-written mappers (ADR-16), which also check the domain rules in release builds.
