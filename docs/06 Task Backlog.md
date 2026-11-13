---
tags: [backlog, tasks]
created: 2026-11-12
---
# 06 Task Backlog

Format: `- [ ] **T-xxx Title** — what / definition of done. _depends:_ …

## M0 — Environment & skeleton
- [ ] **T-001 Install toolchain** — Flutter stable, Android SDK (cmdline-tools or Android Studio), JDK 17, platform-tools; accept licences. DoD: `flutter doctor` shows no errors for Android; a phone with USB debugging appears in `flutter devices`.
- [ ] **T-002 Create project** — `flutter create --platforms=android --org <org> tasks_order`; set `minSdk 26`; `git init`, `.gitignore`, first commit. DoD: default counter app runs on the phone. _depends:_ T-001
- [x] **T-003 Dependencies & tooling** — add `flutter_riverpod`, `riverpod_annotation`, `drift`, `sqlite3_flutter_libs`, `path_provider`, `go_router`, `freezed_annotation`, `uuid`, `flutter_localizations`, `intl`, `shared_preferences`; dev: `build_runner`, `drift_dev`, `freezed`, `riverpod_generator`, `flutter_lints`. Strict `analysis_options.yaml`. VS Code task / script for `build_runner watch`. DoD: `flutter analyze` clean, codegen runs. _depends:_ T-002
  - _Notes (2026-11-13):_ `sqlite3_flutter_libs` dropped (obsolete with `sqlite3` 3.x); `json_serializable` deferred to T-502 (ADR-8 in [[02 Architecture]]); `build_runner` 2.17 removed `--delete-conflicting-outputs`. Scripts: `tool/gen.sh`, `tool/gen.ps1`, VS Code tasks.
- [x] **T-004 Skeleton & docs** — create folder structure from [[02 Architecture]], empty `domain/`, `data/`, `features/`; `README.md` pointing to `docs/`. DoD: structure in place, app still runs. _depends:_ T-003
  - _Notes (2026-11-13):_ empty folders hold `.gitkeep`; `test/domain/domain_purity_test.dart` enforces "no flutter/drift in lib/domain".
- [ ] **T-005 CI (optional)** — GitHub Actions: `flutter analyze` + `flutter test` on push. DoD: green badge. _depends:_ T-003
  - _Notes (2026-11-13):_ postponed by owner: no GitHub remote yet. Not blocking M0.

## M1 — Domain core (pure Dart, no Flutter imports)
- [ ] **T-101 LocalDate** — value object: constructors, `addDays`, `daysUntil`, `weekday` (Mon=0..Sun=6), `compareTo`, ISO parse/format, equality. DoD: `local_date_test.dart` covers month/year rollovers and leap day.
- [ ] **T-102 Task entity** — freezed `Task`, `TaskStatus` (active/done), factory `Task.create(title, priority, dueDate)` with UUID, `isToday`/`todayFlaggedAt`, `deletedAt`, validation helper `isValidPriority(scale)`, `PriorityLabels.key(priority, scale)` returning a localisation key (`priority.s3.*`, `priority.s5.*`, `priority.s10.*`) and `PriorityLabels.color(priority, scale)`. DoD: tests for invariants, all 18 keys on scales 3/5/10, colour gradient endpoints. _depends:_ T-101
- [ ] **T-103 Settings & capacity resolver** — freezed `Settings` with defaults (urgency thresholds, `todayVisibleLimit`, `dayStartHour`, overflow 1..3), `DayOverride`, `CapacityResolver.capacityFor(date)` = override ?? weekday, `LocalDate.todayFor(DateTime now, int dayStartHour)`. DoD: tests incl. override precedence and day-start rollover at 03:59 vs 04:00. _depends:_ T-101
- [ ] **T-104 Plan model** — `Plan` (incl. `todayQueue`, `todayVisibleLimit`), `PlannedDay`, `PlanEntry`, `PlanReason`. DoD: compiles, `isOverloaded` tested. _depends:_ T-101
- [ ] **T-105 Planner: Today queue & priority fill** — split queue (flagged or overdue) vs pool, `TodayEntry` with `overdueDays`, queue ordering, day loop, pool ordering (without boost yet), horizon, `later`. Scenarios 1–4, 10, 15, 15b, 17, 18 from [[04 Planner Algorithm]]. DoD: tests green. _depends:_ T-102, T-103, T-104
- [ ] **T-106 Planner: deadline forcing** — `forcedToday` with prefix-sum `avail`; due-today forcing. Scenarios 6, 11. DoD: example 1 reproduced exactly (no boost yet). _depends:_ T-105
- [ ] **T-107 Planner: overflow & at-risk** — hardLimit, trim/spill, `overflow`/`atRisk` flags, rest days. Scenarios 7, 8, 9. DoD: example 3 reproduced, with and without overflow. _depends:_ T-106
- [ ] **T-108 Planner: urgency boost** — `effPriority(t, d)` with soon/near thresholds, per-day pool ordering (effPriority, priority, effDue, createdAt), clamp ≥ 1. Scenarios 5, 16. DoD: example 2 reproduced with and without boost. _depends:_ T-107
- [ ] **T-109 Planner: pins & completed-today** — pinned placement, past pins → today, pins reduce `avail`, `completedTodayCount` counts only non-flagged tasks. Scenarios 12, 13, 14. DoD: tests green. _depends:_ T-108
- [ ] **T-110 Planner: performance & determinism** — scenario 19 (500 tasks < 50 ms), 18. Precompute capacity prefix sums. DoD: benchmark test passes on desktop. _depends:_ T-109

## M2 — Data layer
- [ ] **T-201 Drift schema v1** — tables `tasks`, `settings`, `day_overrides` from [[03 Data Model]] incl. `updated_at`/`deleted_at` (D12); `AppDatabase` with `NativeDatabase` + in-memory constructor for tests; seed settings row on create. DoD: codegen OK, schema test. _depends:_ T-003, T-101
- [ ] **T-202 TaskRepository (drift)** — mapper row ↔ `Task`; `watchActive`, `watchAll`, `watchTrash`, `upsert`, `complete`, `uncomplete`, `setToday`, soft `delete`, `restore`, `purgeDeleted`; every write bumps `updatedAt`; queries filter `deleted_at IS NULL`. DoD: tests on in-memory DB, stream emits on each write. _depends:_ T-201, T-102
- [ ] **T-203 Settings, DayOverride & DeviceSettings** — `watch`/`save`, `watchAll`/`upsert`/`remove` (soft); defaults when row missing; `DeviceSettings` (locale, theme, show reasons) in SharedPreferences with `localeProvider`/`themeModeProvider`. DoD: tests. _depends:_ T-201, T-103
- [ ] **T-204 Providers & planProvider** — `databaseProvider`, repository providers, `settingsProvider`, `activeTasksProvider`, `dayOverridesProvider`, `planProvider` combining them + `completedTodayCount` (non-flagged tasks with `completedAt` on today, respecting `dayStartHour`), debounced 50 ms. DoD: provider test with `ProviderContainer` and in-memory DB. _depends:_ T-202, T-203, T-109
- [ ] **T-205 Today provider** — `todayProvider` emitting `LocalDate` now and at the next `dayStartHour` boundary (timer, re-armed when the setting changes), injectable clock for tests. DoD: unit test with fake timer at midnight and at 04:00. _depends:_ T-101, T-103

## M3 — MVP UI (v0.1)
- [ ] **T-301 App shell, l10n & themes** — `MaterialApp.router` with `localizationsDelegates` (uk, en) driven by `localeProvider`, Material 3 light/dark driven by `themeModeProvider`, `go_router` with bottom nav: Today, Plan, Tasks, Settings; routes `/task/:id`, `/task/new`. ARB files with the tab names; lint rule/convention: no string literals in widgets. DoD: navigation works on device; switching system language and theme is reflected. _depends:_ T-004, T-203
- [ ] **T-302 Today screen** — section "Today" (`todayQueue.take(limit)` sorted by priority, "+N more" counter, checkbox → complete, next queued task appears, overdue badge "overdue by N days" with move/clear due date actions), section "Planned n/capacity" with entries (title, priority label chip, due, reason badge), checkbox → complete with undo snackbar and **no** refill, overloaded banner, empty state. DoD: widget tests for refill vs no-refill, in uk and en, light and dark. _depends:_ T-204, T-301
- [ ] **T-303 Add/Edit task screen** — title (autofocus), notes, priority picker scaled to `priorityScale` showing localised **"Label (n)"** entries from the D1 tables (uk + en in ARB) with colours, due date picker (+ clear), **Today** toggle, save/delete (delete → Trash with undo); validation. DoD: creates/updates a task, visible on Today/Tasks. _depends:_ T-202, T-301
- [ ] **T-304 Tasks screen** — all active tasks sorted by pool order, Today-flagged marked; filter chips: all / today / due / later (not in horizon); swipe right → complete, swipe left → Today flag; tap → edit; FAB → new. DoD: shows "later" tasks from `plan.laterTaskIds`. _depends:_ T-204, T-303
- [ ] **T-305 Settings screen** — priority scale (3/5/10) segmented, weekly capacity editor (7 steppers), overflow (+1/+2/+3), horizon, Today visible limit, day start hour; "Advanced": urgency thresholds; language (Device default / Українська / English) and theme (Device default / Light / Dark) as device settings, default = device. DoD: changes recompute the plan instantly; language and theme switch immediately without restart; fresh install follows the phone's language and theme. _depends:_ T-203, T-301
- [ ] **T-306 Done list** — tab or section in Tasks: completed tasks grouped by day, uncomplete action. DoD: works. _depends:_ T-304
- [ ] **T-307 Quick add & polish** — quick-add bottom sheet from Today (title + priority only), haptics, consistent paddings. DoD: add a task in under 5 s. _depends:_ T-302, T-303
- [ ] **T-308 Device test & debug APK** — manual walkthrough of all MVP stories from [[01 Brainstorm]]; fix findings; `flutter build apk --debug`. DoD: APK installed, retro notes added to [[05 Roadmap]]. _depends:_ T-302 … T-307

## M4 — Plan control (v0.2)
- [ ] **T-401 Plan screen** — upcoming days list: date header with `n/capacity`, entries with reason badges, overloaded marker, "Later (N)" section, header "N at risk". DoD: matches planner output. _depends:_ T-204, T-301
- [ ] **T-402 Pin to date** — from task editor and from Plan (long press → move to day); unpin. DoD: pinned badge appears, planner respects it. _depends:_ T-401, T-108
- [ ] **T-403 Day override editor** — tap a day header → set capacity for that date / reset, optional note. DoD: override stored, plan updates. _depends:_ T-401, T-203
- [ ] **T-404 At-risk resolution** — tapping an at-risk task offers: move due date, drop task, add +1 capacity today (creates override). DoD: each action clears the flag. _depends:_ T-401
- [ ] **T-405 Trash** — list of soft-deleted tasks (30 days) with restore and "delete forever"; automatic purge on app start. DoD: restored task returns to the plan. _depends:_ T-304
- [ ] **T-406 Priority scale migration** — when scale shrinks, remap priorities proportionally (10→5: ceil(p/2)) after confirmation; when it grows keep values. DoD: tested mapping. _depends:_ T-305

## M5 — Polish & release (v0.3)
- [ ] **T-501 Morning notification** — `flutter_local_notifications`, daily at configurable time, body = today's task titles; Android 13 permission flow. DoD: notification arrives on device. _depends:_ T-308
- [ ] **T-502 Backup / restore** — export JSON via share sheet, import from file picker with confirmation. DoD: round-trip test. _depends:_ T-202, T-203
- [ ] **T-503 Branding & l10n pass** — app name (localised), icon (`flutter_launcher_icons`), splash, dark theme pass on every screen, review of all uk/en strings, date formats per locale. DoD: looks finished on the launcher in both languages. _depends:_ T-308
- [ ] **T-504 Tests** — widget tests for Today/Editor/Settings, one integration test happy path. DoD: `flutter test` + `integration_test` green. _depends:_ T-308
- [ ] **T-505 Release build** — keystore, `key.properties`, R8, `flutter build apk --release`, install. DoD: release APK runs. _depends:_ T-503
- [ ] **T-506 Docs** — user guide page in Obsidian, changelog, update [[02 Architecture]] with anything that drifted. DoD: docs match code. _depends:_ T-505

## Parking lot (not scheduled)
- Sync between devices (SyncEngine behind the existing repositories; LWW on `updatedAt`, tombstones via `deletedAt`)
- Family group: partner sees my load (n/capacity per day), proposes tasks into my queue (`proposed` status, accept/decline), `ownerId`/`assigneeId`
- Plan cache for home-screen widget / notification (D2)
- Not-before / snooze date
- Recurring tasks
- Effort estimate and capacity in points
- Tags / projects, subtasks
- Stats and streaks
- Home-screen widget
- Sync / multi-device
- "+1 more" button on Today (pull next task after completing)
