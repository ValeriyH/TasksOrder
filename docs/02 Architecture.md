---
tags: [architecture]
created: 2026-11-12
updated: 2026-11-20
---
# 02 Architecture

## Tech stack
| Concern | Choice | Notes |
|---------|--------|-------|
| Framework | Flutter 3.50 (stable), Dart 3.14 | Android first; `minSdk 24`, `compileSdk`/`targetSdk` 36. Widgets from `package:material_ui` (Material split out of the framework in 3.50) |
| State / DI | `flutter_riverpod` + `riverpod_annotation` | Providers compose streams from the data layer; the plan is a derived provider |
| Persistence | `drift` (SQLite via `sqlite3` 3.x build hooks) | Type-safe schema, migrations, reactive queries, in-memory DB for tests |
| Models | `freezed` | Immutable entities; `Recurrence` is a plain sealed class (refuses a broken rule in release builds) |
| Navigation | `go_router` | 4 tabs in a `StatefulShellRoute.indexedStack` + the task editor route |
| Codegen | `build_runner` | drift_dev, freezed, riverpod_generator; `tool/gen.sh` / `tool\gen.ps1` |
| Dates | own `LocalDate` | A task is due on a calendar day, never a `DateTime` |
| Localisation | `gen-l10n` from `lib/l10n/app_en.arb`, `app_uk.arb` | English is the template and fallback; a test forbids string literals in widgets |
| Theme | Material 3 `ColorScheme.fromSeed` + `AppColors` (`ThemeExtension`) | Tokens of the redesign for light and dark (ADR-23) |
| Device prefs | `shared_preferences` | locale, theme, reason badges, notification time |
| Notifications | `flutter_local_notifications` 22.x + `timezone` | 22.x because 23.x needs `compileSdk 37` (ADR-20) |
| Files | `file_picker` | Backup save / open dialogs (ADR-16) |
| Branding | `flutter_launcher_icons`, `flutter_native_splash` (dev) | Generated from `assets/icon/` (ADR-21) |
| Lint | `flutter_lints` + `strict-casts`, `strict-inference`, `strict-raw-types` | `test/domain/domain_purity_test.dart` enforces the domain import rule |
| Tests | `flutter_test`, `integration_test` | Planner: table-driven unit tests |

## Platforms
| Platform | Role |
|----------|------|
| Android | Product target. Emulator `TasksOrder_API36` (Pixel 6, Android 16) for walkthroughs; the owner's phone gets releases in batches |
| Windows desktop | Fast development target (hot reload, native SQLite). Needs VS Build Tools 2022 (C++, ATL for the notifications plugin) and Developer Mode (symlinks) |
| Web (Chrome) | Demos; GitHub Pages: https://valeriyh.github.io/TasksOrder/. drift on SQLite wasm + a worker (`web/sqlite3.wasm`, `web/drift_worker.js`, refreshed by `dart run tool/web_assets.dart` after a drift / sqlite3 upgrade). Data lives in IndexedDB of the site: clearing site data deletes the tasks |

## Layers
```
presentation  (features/*, shared/: screens, widgets)            Flutter + Riverpod
      |  reads providers, calls actions
application   (providers, TaskActions, derived payloads)        Riverpod
      |  calls
domain        (entities, Planner, LocalDate, repository APIs)   pure Dart, NO flutter imports
      ^  implemented by
data          (drift database, repositories, backup codec)      drift, shared_preferences
```
- `lib/domain` imports neither `package:flutter` nor `package:drift`.
- Repositories expose streams (`Stream<List<Task>>`, `Stream<Settings>`); the UI never touches drift rows.
- Storage is an adapter: the local store today, a remote data source behind a `SyncEngine` later (D12); replacing either must not touch domain, providers or UI.
- `planProvider` = `Planner.plan(tasks, settings, overrides, today, completedTodayCount)`, recomputed synchronously on every input change (ADR-13). See [[04 Planner Algorithm]].
- `todayProvider` emits a new `LocalDate` when local time crosses `dayStartHour` (D15): one timer for the next day start, also invalidated on resume.
- Consumers that cannot compute the plan get derived payloads: `morningScheduleProvider` (notifications, ADR-20) and `homeWidgetPayloadProvider` (widget, ADR-22); `TasksOrderApp` hands every new value to the platform.

## Project structure
```
lib/
  main.dart
  l10n/          app_en.arb, app_uk.arb (generated/ is not committed)
  app/           app.dart, app_shell.dart, router.dart, theme.dart, app_colors.dart (tokens, AppDims, PriorityShade)
  domain/
    model/       task, recurrence, series, settings, device_settings, day_override, plan, local_date, priority_labels, task_size, backup
    planner/     planner.dart, capacity_resolver.dart
    notification/ morning_digest.dart
    widget/      widget_days.dart
    repository/  interfaces: Task, Settings, DayOverride, DeviceSettings, Backup repositories; NotificationScheduler; HomeScreenWidget
  data/
    db/          database.dart (tables, migrations), converters.dart
    repository/  drift implementations, SharedPreferences device settings
    backup/      backup_codec.dart, picker_backup_file_store.dart
    notifications/ local_notification_scheduler.dart
    home_widget/ channel_home_screen_widget.dart
  application/   providers.dart, device_settings_providers.dart, task_actions.dart, notifications.dart, home_widget.dart, backup.dart
  features/      today/ (+ quick_add_sheet), plan/ (+ day_override_dialog), tasks/, task_edit/ (+ repeat_sheet, days_sheet), trash/, settings/
  shared/        task_card.dart (TaskCard, GhostTaskCard, TaskNotes, chips), task_actions_ui.dart (menus, snack bars), plan_badges.dart, priority_*.dart, screen_header.dart, …
android/app/src/main/kotlin/…/  MainActivity.kt (method channel), TodayWidgetProvider.kt (widget)
test/            domain/, data/ (in-memory drift, schema migrations), application/, features/ (app_harness.dart), shared/
integration_test/ app_test.dart
drift_schemas/   schema snapshots v1 … v6
tool/            gen.sh/.ps1, run_windows.cmd, run_web.cmd, start_emulator.cmd, web_assets.dart
```

## Key flows
- **Add / edit:** editor or quick add → `TaskActions` → `TaskRepository.upsert(task, now)` → stream emits → plan recomputes → screens rebuild.
- **Complete:** Done button → `TaskRepository.complete(id, now, onPlan:, plannedDate:, today:)`. `onPlan` = the task is on today's list (D19, stored as `completedOnPlan`); `plannedDate` = the day of the entry shown (stored as `completedPlanDate`, D22). A recurring task gets its successor in the same transaction (ADR-18). "Completed" undoes (`uncomplete`; only the last completion of a series).
- **Recurring:** the editor's Repeat sheet sets `recurrence`, `seriesId`, `occurrenceDate`; the planner adds ghosts for the horizon; complete or skip stores the next instance. Nothing is written at rollover.
- **Day rollover:** `todayProvider` emits → plan recomputes; unfinished tasks return to the pool, past due dates make tasks overdue (D18). No writes.
- **Today screen:** header with date and progress (done from today's list / that + left); **Focus** (`plan.visibleFocus`, "+N more", then tasks done from Focus, dimmed); **Planned** (today's entries with chips, then done ones, dimmed); banners for at-risk (D16) and overload; empty state as a card. A tap opens the task menu.

## Error handling and edge cases
- A priority level the scale does not offer is shown as the nearest one and stored unchanged (ADR-17).
- No capacity anywhere → every task is Later; Today explains.
- 500 tasks × 90 days plan in about 2 ms, so there is no debounce (ADR-13); with 20 daily series the pool is sorted only when needed (M8).

## Testing
1. **Planner** — the table of [[04 Planner Algorithm]] in `test/domain/planner*_test.dart`; every UI bug in the planner becomes a row first.
2. **Data** — drift in memory (`newTestDatabase()`), streams, schema migrations with `SchemaVerifier` (`test/data/database_schema_test.dart`), backup codec.
3. **Widgets** — screens through `AppHarness` (fake clock, in-memory DB), both languages and themes where it matters; contrast of the colour tokens (`app_colors_test.dart`).
4. **Integration** — `integration_test/app_test.dart`: quick add, edit, complete, find under Done. `flutter test integration_test -d <device>`; CI runs only `test/`.
5. **Walkthrough** — release APK on the emulator over the previous release at each milestone end (bugs that tests missed were found there).

## Gotchas
Toolchain and build:
- Build Windows from one drive-letter casing only: `d:\` vs `D:\` wipe `windows/flutter/ephemeral` for each other (`tool/run_windows.cmd` normalises it).
- `kotlin.incremental=false` (ADR-9): project on D:, pub cache on C:.
- Flutter 3.50: Material widgets come from `package:material_ui`; `build_runner` 2.17 has no `--delete-conflicting-outputs`.
- After `flutter test`, a release build can fail on `integration_test` in `GeneratedPluginRegistrant.java`: delete that git-ignored file; `flutter clean` would also wipe the generated l10n.
- Release builds: the notifications plugin needs Gson keep rules and `keep.xml` for an icon named only from Dart; an occasional first Gradle failure goes away on a rerun.
- PowerShell `Set-Content -Encoding utf8` writes a BOM; Python scripts that write text files need `newline=''` (the repo wants LF).
- `file_picker` dialogs cannot be driven over adb: backup / restore is covered by tests.

Code:
- drift: `insertOnConflictUpdate` with a row class skips nulls (use `toCompanion(false)`); `dateTime()` stores seconds, so instants are integer ms; a `Set` column compares by identity in row equality; `drift/native.dart` must stay out of `lib/` (web build); in a migration do not mix the two `CASE` forms.
- Riverpod under `fake_async` needs `async.elapse(Duration.zero)`; a drift call awaited in a widget test needs `tester.runAsync`.
- gen-l10n folds `=1` and `one` into one branch: "every day" needs its own key. ARB message names must be Dart identifiers (ADR-11).
- `Dismissible` used only as a trigger returns false from `confirmDismiss`; two FABs in a tab stack need their own `heroTag`; `excludeSemantics` needs `onTap` on the `Semantics` or the button cannot be pressed by a screen reader.
- A `ListView` with its own `padding` does not add the safe area: add `MediaQuery.paddingOf(context).bottom` (lists without an app bar also need the top, `TabBody`).
- freezed constructors with method-calling assertions cannot be `const`.

Emulator (`tool\start_emulator.cmd [--wait]` or F5 "TasksOrder (Android)"):
- `uiautomator dump` reads Flutter semantics: drive by labels, not guessed coordinates; a card's chips and title come as one label; match exact labels (a hint starting with a segment name catches a prefix match). Screenshots are scaled: multiply by the ratio to the real resolution.
- `adb shell input text` types Latin only; Enter in a multi-line field is `keyevent 66`.
- `adb root` + `settings put global auto_time 0` move the clock (put it back after); `adb root` also allows reading the app's files (`files/tasks_order.sqlite`, `shared_prefs/today_widget.xml`) with the system `sqlite3`; `adb unroot` after.
- `adb reboot` closes the emulator: `adb emu kill` and a new start give a cold boot. Inexact alarms can come at the end of their window (4.5 min).
- Installing the integration test's debug APK replaces a release-signed app and its data; the integration test on the emulator wipes app data (on Windows it keeps it).
- A debug build left by a closed debug session can show a white screen until restarted.

## Non-goals (for now)
- Backend, accounts, sync, family group — kept possible by D12 (UUIDs, `updatedAt`, soft delete, repository interfaces, planning vs device settings).
- iOS and macOS builds (possible, not tested).
- Time-of-day scheduling: the unit is a day.

## Architecture decisions
Superseded ones (ADR-5, ADR-8 in part) are in [[Superseded decisions]].
- **ADR-1** derived plan, not persisted (D2).
- **ADR-2** one app package with a `domain` folder; can become `packages/core` if the planner is reused.
- **ADR-3** calendar dates as ISO `yyyy-MM-dd` text; instants as UTC epoch milliseconds.
- **ADR-4** sync-ready rows (UUID, `updatedAt`, `deletedAt`) since schema 1; no sync code (D12).
- **ADR-6** localisation via ARB from the first screen; English is the source language of ARB files and docs.
- **ADR-7** no "dropped" status; delete is a soft delete = Trash = sync tombstone (D14).
- **ADR-8** no `json_serializable`; backup mappers are hand-written in `data/backup` (ADR-16).
- **ADR-9** `kotlin.incremental=false` (different drives for project and pub cache).
- **ADR-10** develop on Windows and web besides Android; logic is platform-independent and verified by `flutter test`.
- **ADR-11** priority presentation in the domain without Flutter types: `PriorityLabels.color` is an ARGB int, `PriorityLabels.key` a logical key mapped to `AppLocalizations` getters (a test keeps the mapping complete).
- **ADR-12** Focus is a planner output (`Plan.focus`: focused or overdue, with the day each landed on); every active task is planned; `completedOnPlan` feeds `completedTodayCount` (D17–D19).
- **ADR-13** `planProvider` is synchronous, no debounce; `AsyncValue<Plan>` loading until all inputs arrive. Active and done tasks come from one stream, so a completion is one change (the slot cannot refill for a frame). Revisit if the done history makes that stream slow.
- **ADR-14** app shell: `go_router` with `StatefulShellRoute.indexedStack`, editor as a top-level route, locations in `AppRoutes`; web keeps hash URLs (GitHub Pages); language and theme read synchronously from preferences so the first frame is right.
- **ADR-15** release signing with a key outside the repo (`android/key.properties`, git-ignored); without it the release is debug-signed (CI, fresh clones) and cannot update a release install. Keep copies of the keystore and passwords. Version = `version:` in `pubspec.yaml`; the build number grows with every APK installed over an older one.
- **ADR-16** backup = one JSON file with all tasks (Trash too), day overrides and planning settings, via the system save / open dialogs; restore replaces everything in one transaction after a confirmation, no merge. The codec checks the domain rules (assertions are off in release). A newer `version` is refused; older ones are read. Format in [[03 Data Model]].
- **ADR-17** fixed priority levels 1..10; the scale only chooses the offered levels (`PriorityLabels.levels`), `nearest` for display, `raise` for the boost. Schema 2 / backup 2 converted old positions to levels.
- **ADR-18** recurring tasks: the rule lives on the task (JSON column); no series table or template; the successor is a copy made in the completing transaction, its id a UUID v5 of `next/<id>` (same on every device, found by undo); `seriesId` and `occurrenceDate` keep history and schedule; future repeats are ghosts; `notBefore` is a release date. Schema 3 / backup 3.
- **ADR-19** task size: `Task.weight` in half-slots (1, 2, 4; default 2), integer arithmetic, sizes changeable without migration; capacity settings stay in normal tasks and the planner doubles them; `effWeight = min(weight, 2 × max(weeklyCapacity))` at planning time. Schema 5 / backup 5.
- **ADR-20** morning notification: the next seven mornings scheduled as single notifications from the plan on every change of plan, language or time; id = plan date; inexact alarms (no special permission), instant built from local fields in UTC (no tz database); survives reboot (`RECEIVE_BOOT_COMPLETED`). Hidden on web and Windows. No background job.
- **ADR-21** branding: icon (three shortening bars with a check, white on `#3F51B5`) and splash generated from `assets/icon/`; name "TasksOrder" in both languages; edge-to-edge with the navigation bar following the app theme (`systemBarsStyle`).
- **ADR-22** home-screen widget: the app sends a cache of the next seven plan days (texts in the app language, up to 8 lines with priority dot colours, `dayStartHour`, a stale text) over the method channel `tasks_order/home_widget`; `TodayWidgetProvider` (Kotlin, `RemoteViews`) stores it in SharedPreferences `today_widget`, picks the current plan day itself and redraws at the next day start (inexact alarm) and every 30 min. A tap opens the app; follows the device light / dark mode. No `home_widget` package (keep it in mind for interactive check boxes). Format in [[03 Data Model]].
- **ADR-23** redesign: `AppColors` tokens (light / dark) with the Material scheme tuned from them; priority chip shades derived from `PriorityLabels.color` with a 4.5:1 contrast test, not the package's five colours; one shared `TaskCard` / `GhostTaskCard`; a done task keeps its plan day (`completedPlanDate`, schema 4 / backup 4). Card v2 (T-1103, `CARD_SPEC.md`): title first, chips in a `Wrap` by `ChipSlot`, quiet chips, loud only levels 1–2 and At risk; notes block (T-1105).
- **ADR-24** a rule from completion has no ghosts; its next instance comes from the completion (today + every) or the skip (`max(today, pin ?? occurrenceDate)` + every), pinned if the instance was pinned, else released on that date.
- **ADR-25** allowed days: `Task.allowedWeekdays` (0..6, Monday = 0; null = any, never empty or all seven) is a property, not a repeat; one more "may be placed on d" test in fill, overflow and forced picks; a pin is placed as is, a past pin goes to the nearest allowed day; forcing checks each distinct set; `effWeight` is capped by the biggest weekday of the set. Schema 6 / backup 6.
