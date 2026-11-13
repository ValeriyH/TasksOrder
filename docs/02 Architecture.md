---
tags: [architecture]
created: 2026-11-12
---
# 02 Architecture

## Tech stack
| Concern | Choice | Notes |
|---------|--------|-------|
| Framework | Flutter 3.50 (stable), Dart 3.14 | Android target first; `minSdk 24` (Android 7.0, test phone on 7.1). Widgets come from `package:material_ui` (Material split out of the framework in 3.50) |
| State / DI | `flutter_riverpod` + `riverpod_annotation` | Providers compose streams from the data layer; the plan is a derived provider |
| Persistence | `drift` (SQLite; native library via `sqlite3` 3.x build hooks, no `sqlite3_flutter_libs`) | Type-safe schema, migrations, reactive `watch()` queries, in-memory DB for tests |
| Models | `freezed` | Immutable entities with `copyWith`, equality. Backup JSON is a data-layer concern (T-502); `json_serializable` deferred, see ADR-8 |
| Navigation | `go_router` | 4 top-level tabs + task editor route |
| Codegen | `build_runner` | drift_dev, freezed, riverpod_generator |
| Dates | own `LocalDate` value object | Avoid timezone bugs: a task is due on a *calendar day*, never a `DateTime` |
| Localisation | `flutter_localizations` + `intl` (ARB: `lib/l10n/app_en.arb`, `app_uk.arb`) | Ukrainian and English; `localeProvider` overrides the system locale (D13). No hard-coded UI strings. |
| Theme | Material 3 `ColorScheme.fromSeed`, `themeModeProvider` | system / light / dark (D13); both themes checked on every screen |
| Device prefs | `shared_preferences` | locale, theme, showReasons, notification time |
| Notifications (v0.2) | `flutter_local_notifications` | Morning summary |
| Lint | `flutter_lints` + stricter rules in `analysis_options.yaml` | `strict-casts`, `strict-inference`, `strict-raw-types`; `test/domain/domain_purity_test.dart` enforces the domain import rule |
| Tests | `test`, `flutter_test`, `integration_test` | Planner: table-driven unit tests |

## Platforms
| Platform | Role |
|----------|------|
| Windows desktop | Main development target from M0 (fast run, hot reload, native SQLite like Android). Needs VS Build Tools 2022 (C++) and Windows Developer Mode (symlinks for plugins). |
| Web (Chrome) | Second target: quick demos, candidate client for future sync. drift uses SQLite wasm + a worker (T-206). Browser storage can be cleared by the user. |
| Android | Product target. Device testing from M3 on the 7.1 test phone (`minSdk 24`). |

## Layers
```
presentation  (features/*: screens, widgets, controllers)      Flutter + Riverpod
      |  reads providers, dispatches intents
application   (providers: repositories, planProvider, clock)   Riverpod
      |  calls
domain        (entities, settings, Planner, LocalDate)         pure Dart, NO flutter imports
      ^  implemented by
data          (drift Database, DAOs, repository impls, mappers) drift
```
Rules:
- `lib/domain` must not import `package:flutter` or `package:drift`. It is the product core and is tested with plain `dart test`.
- Repositories expose `Stream<List<Task>>`, `Stream<Settings>`; the UI never touches drift rows.
- **Storage is an adapter, not a dependency.** Two independent adapters sit behind domain interfaces: the *local store* (always present, offline-first; drift today: native SQLite on Android/Windows, SQLite wasm in the browser, opened via `drift_flutter`) and, later, a *remote data source* used by a `SyncEngine`. The remote side is backend-agnostic (SQL, NoSQL, even a Google Sheet): it only needs to store rows keyed by UUID with `updatedAt`/`deletedAt`. Replacing either adapter must not touch domain, providers or UI.
- `planProvider` = `Planner.plan(tasks, settings, overrides, today)` recomputed whenever any input stream emits. See [[04 Planner Algorithm]].
- A `todayProvider` emits a new `LocalDate` when the local time crosses `settings.dayStartHour` (default midnight, D15) so the plan rolls over without restart. "Today" for a `DateTime` = calendar date of `(now - dayStartHour)`.

## Project structure
```
tasks_order/
  lib/
    main.dart
    l10n/           # app_en.arb, app_uk.arb (generated AppLocalizations)
    app/            # MaterialApp, theme, router, bottom navigation
    domain/
      model/        # task.dart, settings.dart, day_override.dart, plan.dart, local_date.dart
      planner/      # planner.dart (+ helpers: capacity_resolver.dart, deadline_forcing.dart)
      repository/   # abstract TaskRepository, SettingsRepository, DayOverrideRepository
    data/
      db/           # database.dart (drift tables), migrations
      repository/   # drift implementations + mappers
    application/
      providers.dart   # database, repositories, clock, planProvider
    features/
      today/        # today_screen.dart, widgets
      plan/         # plan_screen.dart (upcoming days)
      tasks/        # tasks_screen.dart (all / done / trash)
      task_edit/    # task_edit_screen.dart
      settings/     # settings_screen.dart, capacity_editor.dart
    shared/         # common widgets: priority_chip, reason_badge, date_pickers
  test/
    domain/         # planner_test.dart (table-driven), local_date_test.dart
    data/           # repository tests on in-memory drift DB
    features/       # widget tests
  integration_test/
  docs/             # this Obsidian vault
```

## Key flows
### Add task
TaskEditScreen → `TaskRepository.upsert(task)` → drift emits new task list → `planProvider` recomputes → Today/Plan screens rebuild.

### Complete task
Checkbox → `TaskRepository.complete(id, now)` → task leaves the active pool → plan recomputes. A planned slot is not refilled today (D3): the planner receives `completedTodayCount` (tasks completed today that were **not** Today-flagged) and reduces today's capacity by that amount. Completing a Today-flagged task does not affect capacity; the queue simply shows the next flagged task (D11).

### Today flag
Checkbox "Today" on a task (editor, list swipe action, Today screen) → `TaskRepository.setToday(id, true, now)` → task moves from the pool into `plan.todayQueue`. Unflagging moves it back and the planner places it again.

### Today screen composition
1. Section **Today** — `plan.todayQueue.take(todayVisibleLimit)`, sorted by priority, counter "+N more" when the queue is longer; overdue entries carry a red "overdue by N days" badge with *move due date / clear due date* actions. Empty section is hidden.
2. Section **Planned n/capacity** — `plan.days.first.entries` with reason badges, overflow banner when overloaded.
3. Empty state when both are empty.

### Day rollover
`todayProvider` emits a new `LocalDate` → plan recomputes from the new today; unfinished planned tasks return to the pool; tasks whose due date is now in the past appear in the Today queue with an overdue badge (D7). Nothing is written to the database at rollover.

## Error handling and edge cases
- Priority outside the current scale (after scale change) → clamp on read, offer migration (T-406).
- Empty capacity everywhere → every task is "Later"; Today shows an explanatory empty state.
- Hundreds of tasks → planner is O(days × tasks log tasks); recompute is debounced (50 ms) in `planProvider`.

## Testing strategy
1. **Planner** — table-driven tests from [[04 Planner Algorithm]] (`test/domain/planner_test.dart`). Each scenario: inputs → expected day/task map + flags. Must run under 1 s total.
2. **Repositories** — drift in-memory DB (`NativeDatabase.memory()`), verify streams emit on change.
3. **Widgets** — Today screen renders the Today queue (3 visible + counter), reasons and the overloaded banner; editor validates priority. Golden/widget tests run in both `uk` and `en` and both themes for the Today screen.
4. **Integration** — one happy path: add 3 tasks, set capacity, verify Today, complete one, verify Plan.

## Non-goals (for now) and how the design keeps them possible
- **Backend, accounts, sync, family group** — not built. Kept possible by D12: UUID ids, `updatedAt`, soft delete, repository interfaces, planning settings separated from device settings. A future `SyncEngine` would observe the same repositories and push/pull rows; the UI would not change.
- iOS and macOS builds (kept possible, not tested)
- Time-of-day scheduling (the unit is a day, not an hour)

## Architecture decisions log
- ADR-1 (2026-11-12): derived plan, not persisted — see D2 in [[01 Brainstorm]].
- ADR-2 (2026-11-12): single app package with a `domain` folder instead of a separate Dart package. Can be extracted into `packages/core` later if the planner is reused (CLI, web).
- ADR-3 (2026-11-12): calendar dates stored as ISO `yyyy-MM-dd` text in SQLite; instants (`createdAt`, `completedAt`) as UTC epoch milliseconds.
- ADR-4 (2026-11-12): sync-ready rows (UUID, `updatedAt`, `deletedAt`) from schema v1; no sync code until the local app proves useful. See D12 in [[01 Brainstorm]].
- ADR-5 (2026-11-13): the Today queue is a planner output (`Plan.todayQueue`), not a UI filter, so widgets/notifications get it for free. Supersedes the "Critical tier" idea from 2026-11-12.
- ADR-6 (2026-11-13): localisation via ARB from the first screen; no string literal in widgets. Ukrainian and English are both first-class; English is the source language of the ARB files and the docs.
- ADR-7 (2026-11-13): no "dropped" status; removal is a soft delete that doubles as Trash and sync tombstone (D14).
- ADR-8 (2026-11-13): `json_serializable` removed from M0 dependencies. Version 6.15.x fails on freezed 4.0.3 output ("Could not resolve annotation for `int get hashCode`"), and older versions conflict with `build_runner` 2.17. Domain entities do not need JSON; backup (T-502) will either re-add it once fixed upstream or use hand-written mappers in `data/`.
- ADR-9 (2026-11-13): `kotlin.incremental=false` in `android/gradle.properties`, because the project (D:) and the pub cache (C:) are on different drives and Kotlin incremental caches fail to close.
- ADR-10 (2026-11-13): develop on Windows desktop and web in addition to Android; Android device testing starts at M3. Logic is platform-independent and verified by `flutter test`; platform differences are confined to the local-store adapter.
