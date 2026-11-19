# Agent rules for TasksOrder

## Git
- **Never commit, push, amend, rebase or reset.** Leave all changes in the working tree; the owner reviews the diff and commits/pushes manually.
- Read-only git commands (`status`, `diff`, `log`, `show`) are fine.
- When a piece of work is done, list the changed files and suggest a commit message instead of committing.

## Workflow
- Chat with the owner in Ukrainian; code, comments, commit messages and developer docs in `docs/` in English; user-facing docs (the user guide) in English and Ukrainian, kept in step (`docs/08 User Guide.md`, `docs/08 User Guide uk.md`).
- `docs/` is an Obsidian vault and the source of truth: next task comes from `docs/06 Task Backlog.md`; record decisions as ADRs in `docs/02 Architecture.md`.
- Keep `docs/` lean: it describes the app as it is. Closed work leaves the backlog at the end of a milestone (summary to `docs/archive/History.md`, toolchain lessons to "Gotchas" in `02 Architecture.md`, ideas to the parking lot); see "Cycle" in `docs/05 Roadmap.md`. Replaced decisions go to `docs/archive/Superseded decisions.md`.
- `docs/archive/` is history: do not read it for ordinary work, only when the reason behind something matters. `docs/design/` is read only for UI work (its README says what is current).
- `Readme.txt` is the owner's scratchpad: do not edit it.
- Before calling a task done: `dart format lib test`, `flutter analyze` clean, `flutter test` green (CI checks all three).
