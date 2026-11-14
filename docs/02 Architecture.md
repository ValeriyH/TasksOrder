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
| Web (Chrome) | Second target: quick demos, candidate client for future sync. drift uses SQLite wasm + a worker (`web/sqlite3.wasm`, `web/drift_worker.js`, refreshed by `dart run tool/web_assets.dart` after a `drift`/`sqlite3` upgrade, T-206). Data lives in the browser's storage for the site: IndexedDB on GitHub Pages and under `flutter run -d chrome` (no COOP/COEP headers, so no OPFS). **Clearing the site data in the browser deletes all tasks**, and another browser or profile starts empty, until backup (T-502) or sync exists. |
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
- A `todayProvider` emits a new `LocalDate` when the local time crosses `settings.dayStartHour` (default midnight, D15) so the plan rolls over without restart. "Today" for a `DateTime` = calendar date of `(now - dayStartHour)`. It is a self-invalidating provider with one timer for the next day start (T-205); the app shell also invalidates it on resume, because timers do not run while the app is suspended.

## Project structure
```
tasks_order/
  lib/
    main.dart
    l10n/           # app_en.arb, app_uk.arb (generated AppLocalizations)
    app/            # MaterialApp, theme, router, bottom navigation
    domain/
      model/        # task.dart, settings.dart, device_settings.dart, day_override.dart, plan.dart, local_date.dart
      planner/      # planner.dart (+ helpers: capacity_resolver.dart, deadline_forcing.dart)
      repository/   # abstract TaskRepository, SettingsRepository, DayOverrideRepository, DeviceSettingsRepository
    data/
      db/           # database.dart (drift tables, migrations), converters.dart
      repository/   # drift implementations + mappers, SharedPreferences device settings
    application/
      device_settings_providers.dart   # sharedPreferences, deviceSettings, locale, themeMode
      providers.dart   # clock, database, repositories, tasks/settings/overrides streams, today, planProvider
    features/
      today/        # today_screen.dart, widgets
      plan/         # plan_screen.dart (upcoming days)
      tasks/        # tasks_screen.dart (all, filters, done)
      trash/        # trash_screen.dart
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
TaskEditScreen → `TaskRepository.upsert(task, now)` → drift emits new task list → `planProvider` recomputes → Today/Plan screens rebuild.

### Complete task
Checkbox → `TaskRepository.complete(id, now, onPlan: ...)` → task leaves the active pool → plan recomputes. `onPlan` = the task is in `plan.days.first.entries` at that moment; the UI knows it, the stored task remembers it as `completedOnPlan` (D19).
- From today's list (`onPlan: true`): the slot is not refilled today (D3). The planner receives `completedTodayCount` (tasks completed today with `completedOnPlan`) and reduces today's capacity by that amount.
- From anywhere else: Focus strip, Plan, Tasks (`onPlan: false`): today's list does not change; the slot the task held on a later day is planned again.

### Focus
Toggle "Focus" on a task (editor, list swipe action) → `TaskRepository.setFocus(id, true, now)` → the task stays where the planner put it and also appears in `plan.focus`. Removing the mark changes nothing in the plan (D17).

### Today screen composition
1. Section **Focus** — `plan.visibleFocus`: focused and overdue tasks that are not on today's list, sorted by priority, counter "+N more" (`plan.hiddenFocusCount`), a "planned for <day>" hint from `plannedDate`; overdue entries carry a red "overdue by N days" badge with *move due date / clear due date* actions. Empty section is hidden.
2. Section **Planned n/capacity** — `plan.days.first.entries` with reason badges, the focus mark and the overdue badge where they apply, overflow banner when overloaded. Deadline-forced entries refill after completion, priority entries do not (D16).
   - When `plan.hasAtRisk`: a warning banner "N tasks will not make their deadline" that opens the list of `plan.atRiskTaskIds`, so the user can pick what matters (D16).
3. Empty state when both are empty.

### Day rollover
`todayProvider` emits a new `LocalDate` → plan recomputes from the new today; unfinished planned tasks return to the pool; tasks whose due date is now in the past are planned as tasks without a date and appear in Focus with an overdue badge (D18). Nothing is written to the database at rollover.

## Error handling and edge cases
- Priority outside the current scale (after scale change) → clamp on read, offer migration (T-406).
- Empty capacity everywhere → every task is "Later"; Today shows an explanatory empty state.
- Hundreds of tasks → planner is O(days × tasks log tasks) and takes about 2 ms for 500 tasks × 90 days, so `planProvider` recomputes on every change without a debounce (ADR-13).

## Testing strategy
1. **Planner** — table-driven tests from [[04 Planner Algorithm]] (`test/domain/planner_test.dart`). Each scenario: inputs → expected day/task map + flags. Must run under 1 s total.
2. **Repositories** — drift in-memory DB (`newTestDatabase()` in `test/data/test_database.dart`, a `NativeDatabase.memory()`), verify streams emit on change.
3. **Widgets** — Today screen renders the Focus strip (3 visible + counter), reasons and the overloaded banner; editor validates priority. Golden/widget tests run in both `uk` and `en` and both themes for the Today screen.
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
- ADR-11 (2026-11-13): priority presentation data lives in the domain without Flutter types. `PriorityLabels.color` returns a plain ARGB `int` (the UI wraps it in `Color`), and `PriorityLabels.key` returns a dotted logical key (`priority.s10.4`). ARB message names must be Dart identifiers, so the UI maps each key to its `AppLocalizations` getter (T-303); a test over `PriorityLabels.allKeys` keeps that mapping complete.
- ADR-12 (2026-11-13): Focus replaces the Today queue (D17–D19 in [[01 Brainstorm]]); supersedes ADR-5 in part. The planner no longer splits a queue off the pool: every active task is planned, an overdue one as a task without a date. Focus is still a planner output (`Plan.focus`, built after the day loop from `isFocused` or overdue, with the day each task landed on), so widgets and notifications get it for free; the strip is that list minus today's entries. `Task.completedOnPlan` replaces the role of the kept Today flag in `completedTodayCount`. Implemented by T-111.
- ADR-13 (2026-11-13): `planProvider` is a synchronous combination of its inputs with no 50 ms debounce (T-204). The planner needs about 2 ms (T-110) and Riverpod already recomputes a provider once per flush, however many inputs changed; a timer would only delay the answer to a checkbox tap and put fake time into tests. It returns `AsyncValue<Plan>`: loading until tasks, settings, overrides and today have all arrived, then data on every change with no loading state in between. Active and done tasks come from one stream (`allTasksProvider`), so a completion reaches the planner as a single change: the task leaves the pool and `completedTodayCount` grows in the same recompute, and the freed slot cannot be refilled for a moment. To revisit if the done history grows large enough to make that stream slow (then: a query for today's on-plan completions only).
- ADR-14 (2026-11-13): app shell (T-301). Navigation is `go_router` with a `StatefulShellRoute.indexedStack` for the four tabs and the task editor as a top-level route pushed above the shell; locations are constants in `AppRoutes`, the router lives in `routerProvider`. The web build keeps the default hash URLs (`#/today`), because GitHub Pages cannot rewrite paths to `index.html`. Texts: Flutter `gen-l10n` from `lib/l10n/app_*.arb` into `lib/l10n/generated/` (not committed, like the other generated code), English is the template and the fallback for a device language the app does not have; widgets read them through `context.l10n`, and a test forbids string literals in widgets. Material and Cupertino texts come from the delegates of `material_ui`, not `flutter_localizations`. Themes: one seed colour, Material 3 light and dark from `ColorScheme.fromSeed`. Language and theme are device settings read synchronously (`sharedPreferencesProvider` is overridden in `main`), so the first frame is already right.
- ADR-15 (2026-11-14): release signing. The release APK is signed with a key that is not in the repository: `android/key.properties` (git-ignored) points to the keystore and holds its passwords, and the Gradle script uses it when the file exists. Without the file the release build is signed with the debug key, so CI and a fresh clone keep building; such an APK cannot update an installation signed with the release key. Android accepts an update only from the same key, and the app has no backup yet (T-502), so losing the keystore or its password means reinstalling and losing the tasks: both files need a copy in a safe place. Version numbers come from `version:` in `pubspec.yaml` (`name+build`); the build number must grow with every APK that is installed over an older one.
- ADR-16 (2026-11-14): backup and restore (T-502). A backup is one JSON file with all tasks (the Trash too), the capacity overrides and the planning settings; device settings stay out (D12). It is written through the system "save as" dialog to a place the user picks, so it survives a reinstall; with it, a lost signing key (ADR-15) costs a reinstall and a restore, not the tasks. Restore replaces everything in one transaction, after a confirmation; there is no merge (that is the job of sync, D12). The mappers are hand-written in `lib/data/backup/backup_codec.dart` (ADR-8) and check the rules of the domain objects themselves, because assertions do not run in a release build. The file carries `version`; a higher one than the app knows is refused, a change of the format raises it and keeps reading the old ones. File dialogs come from the `file_picker` package behind the `BackupFileStore` interface.
- ADR-10 (2026-11-13): develop on Windows desktop and web in addition to Android; Android device testing starts at M3. Logic is platform-independent and verified by `flutter test`; platform differences are confined to the local-store adapter.
