# Agent rules for TasksOrder

## Git
- **Never commit, push, amend, rebase or reset.** Leave all changes in the working tree; the owner reviews the diff and commits/pushes manually.
- Read-only git commands (`status`, `diff`, `log`, `show`) are fine.
- When a piece of work is done, list the changed files and suggest a commit message instead of committing.

## Workflow
- Chat with the owner in Ukrainian; code, comments, commit messages and `docs/` in English.
- `docs/` is an Obsidian vault and the source of truth: next task comes from `docs/06 Task Backlog.md`; record decisions as ADRs in `docs/02 Architecture.md`.
- `Readme.txt` is the owner's scratchpad: do not edit it.
- Before calling a task done: `flutter analyze` clean and `flutter test` green.
