---
tags: [roadmap, planning]
created: 2026-11-12
---
# 05 Roadmap

Each milestone ends with a demo on a real device and a short retro: what new needs appeared → update [[01 Brainstorm]] and [[06 Task Backlog]].

| Milestone | Goal | Outcome | Tasks |
|-----------|------|---------|-------|
| **M0 — Environment & skeleton** | Toolchain works, empty app runs on Windows and in Chrome, Android APK builds | `flutter doctor` clean, project with lint, folder structure, git | T-001 … T-006 |
| **M1 — Domain core** | The planner exists and is proven by tests | `LocalDate`, `Task`, `Settings`, `Planner` (forcing, overflow, urgency boost, pins, Focus view) with the full test table from [[04 Planner Algorithm]] | T-101 … T-111 (T-111 added 2026-11-13: Focus replaces the Today queue) |
| **M2 — Data layer** | Tasks and settings survive restarts, streams drive a live plan | drift schema v1, repositories, device settings, `planProvider`, day-start clock, web storage | T-201 … T-206 |
| **M3 — MVP UI (v0.1)** | Daily usable app, uk/en, light/dark | Today (queue + planned), Tasks, Add/Edit, Settings, Done; debug APK on device | T-301 … T-308 |
| **M4 — Plan control (v0.2)** | User can steer the plan | Plan screen, pins to future dates, day overrides, at-risk resolution, Trash, scale migration | T-401 … T-406 |
| **M5 — Polish & release (v0.3)** | Something you would keep installed | Notification, backup, icon, tests, signed release build | T-501 … T-506 |
| **M7 — Recurring tasks (v0.4)** | Tasks that repeat, with an honest load for the whole horizon | Repeat rules (every N days / weeks / months / years, weekdays; by schedule or from completion), one stored instance per series, ghosts in the Plan, release dates in the planner, schema 3, backup format 3 (D20, ADR-18) | T-701 … T-709 |
| **M8 — Task size (v0.6)** | A small task does not eat a whole day and a large one gets a day that can hold it | Sizes small / normal / large as weights of ½ / 1 / 2 slots, first-fit planning, overflow for a large top-level task, schema 5, backup format 5 (D21, ADR-19) | T-801 … T-806 |
| **M9 — Redesign (v0.5)** | The new look of the owner's mockups, the logic unchanged | Theme tokens for light and dark, a shared task card with a Done button, done tasks kept in sight, a tap opens the task menu, Today with a progress bar, Plan with capacity pills and free slots, Tasks with "Active" and counters on the filters; a done task stays on its plan day (schema 4, backup format 4) (D22, ADR-23) | T-901 … T-907 |

M7 was designed on 2026-11-14 and does not depend on the open tasks of M5 or on the widget (T-601); the owner picks the order. M8 was designed the same day and comes after M7 (owner): both change the same parts of the planner. M9 was designed on 2026-11-15 and is **done before M8** (owner): M8 adds a size to the task card and a load to the day headers, so it is built in the new look from the start. The numbers stay in the order the milestones were planned; M9 is v0.5 and M8 moves to v0.6.

## Suggested order inside the cycle
1. Pick the next unchecked task in [[06 Task Backlog]] (respect `depends`).
2. Write/adjust the test first when the task is domain or data.
3. Implement, run `flutter analyze` and `flutter test`.
4. Tick the task, note anything learned in the task's "Notes" line.
5. At milestone end: device demo, update docs, groom the backlog.

## Risks
- **Toolchain on Windows** (Android SDK licences, JDK version, emulator): time-box T-001 to one evening; a physical phone with USB debugging avoids the emulator.
- **Codegen friction** (`build_runner` for drift/freezed/riverpod): set up a `tool/gen.sh` / VS Code task early (T-003).
- **Planner edge cases**: keep the test table as the contract; every bug found in the UI becomes a new row before it is fixed.
- **Scope creep**: parking lot in [[01 Brainstorm]] exists for a reason.

## Retro
### M9 — 2026-11-15 (done before M8)
- **Done:** T-901 … T-907. Theme tokens for light and dark with priority shades derived from the app's colours and a contrast test; a shared task card with a Done button and chips; Today with the date, progress and sections; Plan with day heads, capacity pills, free slots; Tasks with "Active", counted filters and done tasks kept until the filter changes; a tap opens the task menu everywhere; no Undo snack bar after a completion; a done task keeps its plan day (schema 4, backup format 4); 693 tests. Release 0.5.0+7.
- **Demo:** emulator, release APK over 0.4.0 with the owner's data (schema 3 → 4, the tasks kept; a completion of 0.4.0 from today's list still shows on today); Today, Plan, Tasks, the menu and the editor in light and dark, Ukrainian and English, scales 3 / 5 / 10; a task of tomorrow done from the Plan stayed on tomorrow and the next task moved up, "Completed" brought it back; a task done in Tasks stayed at the end, the counts changed at once; the launch screen in the new background. The owner's smoke test passed before the walkthrough.
- **Changed decisions:** the mockups are a reference, not a contract (the owner's design was made without the project's details): the priority colours stay the app's own, due dates have no time, Today's progress counts today's list and not Focus, the Focus counter is the number of tasks in Focus (owner, after the preview), a done card says "Completed <day>" (owner). A done task stays on the day it was planned for (owner, after T-904), which needed the one data change of M9 (T-907); M8 moves to v0.6 with schema 5 and backup format 5.
- **New backlog items (parking lot):** search over all tasks; fewer tabs (Today as focus, Plan as the schedule with the task list); "Skip this time" for a ghost; a tap on a free slot adds a task to that day; the widget in the new style.
- **Learned:** the reference widget of the design package hid the Done button's tap from screen readers (`excludeSemantics` without `onTap`), found by a semantics test; without an app bar a list scrolls under the status bar, invisible in widget tests and goldens and found on the emulator (fixed with `TabBody`, a test with a status bar padding); goldens with the SDK's Roboto and Material Icons give a fair preview of a screen before the device; the integration test runs on Windows once the ATL component of the Build Tools is in (the notifications plugin needs it; added with the owner's permission), which keeps the emulator's data; on the emulator it wipes the app data.
### M7 — 2026-11-15
- **Done:** T-701 … T-711. Repeat rules (every N days / weeks / months / years by schedule or from completion, weekdays), series fields and the successor, release dates in the planner, ghosts over the horizon, schema 3 with a verified migration, backup format 3, the Repeat sheet in the editor, ghosts in the lists, "Skip this time" in the long-press menu of the Plan and Today, a "Recurring" filter in Tasks, one completion a day for a series from completion; 602 tests. Release 0.4.0+6.
- **Demo:** emulator, release APK over 0.3.1 (the database moved from schema 2 to 3 with the tasks kept): a monthly task without dates, weekdays with a pin, every 10 days from completion; complete, undo, skip; the clock moved three days on (a missed pinned instance is one task today, the ghosts start after it); backup of format 3 and restore of a deleted series.
- **Changed decisions:** `Recurrence` is a plain sealed class, not `freezed`, so a broken rule is refused in a release build too; the successor id is a UUID v5 of `next/<id>` in a namespace of the app; a save of the editor re-anchors only for a new rule or new dates; `restore` also removes the untouched successor of a skip, so Undo of a skip puts everything back.
- **New backlog items:** T-710 and T-711 (from the owner's use on the emulator), done in M7; T-712 (skip from completion counts from the skipped date) and T-713 (untick only the last completion of a series), open in M7.
- **Learned:** the Tasks list mapped task → day over every plan entry, so the last ghost won (found on the emulator, fixed with a test); gen-l10n folds `=1` and `one` into one branch, so "every day" needs its own key; after `flutter test` a release build can fail on `integration_test` in `GeneratedPluginRegistrant.java`: delete that file (git-ignored) instead of `flutter clean`, which also wipes the generated l10n; drift's `SchemaVerifier` needs `drift_dev schema generate` helpers, and the old migration tests had to start from the real schema 1; `adb root` and `settings put global auto_time 0` move the emulator clock. The owner's use found what the scripted walkthrough did not: the ghosts of a series piled up on one free day (a series is now a chain and a ghost without dates expires), a tick on a task from completion done ahead brought a successor on the same date (T-710), and "Skip" hidden behind Delete was not found (T-711).
### M5 — 2026-11-14
- **Done:** T-501 … T-506. Morning notification, icon and launch screen, navigation bar per theme, string review, integration test, release 0.3.0+4, user guide and changelog; 476 tests plus the integration test.
- **Demo:** emulator, release APK driven over adb: the permission dialog, a notification with the day's task, the same after a cold boot; the app in dark Ukrainian on every screen; the icon in the launcher.
- **Changed decisions:** ADR-20 (the notifications of the next week are computed from the plan when the app runs, no background job); ADR-21 (icon and splash generated from `assets/icon/`, the name stays "TasksOrder" in both languages); `flutter_local_notifications` held at 22.x for `compileSdk 36`.
- **New backlog items:** none.
- **Learned:** an inexact alarm can come at the very end of its window (4.5 min); `adb reboot` closes the emulator instead of rebooting it, `adb emu kill` and a new start give a clean cold boot; the notification plugin needs Gson keep rules and a `keep.xml` for an icon named only from Dart; an integration test on a device has to wait for the database (`pumpUntil`) and scroll off-screen chips into view; installing the debug APK of an integration test replaces a release-signed app with its data; on Windows a Python script that writes text files must use `newline=''` or they turn CRLF.
### M3 — 2026-11-14 (closed after M4, with T-308)
- **Done:** T-301 … T-308. The device walkthrough ([[07 Device Test M3]]) ran on the emulator (`TasksOrder_API36`, debug build; midnight and overdue checked by moving the emulator clock); the owner checked the web app (a task survives a reload), vibration and light/dark on the phone. Fixes in 0.2.2; 460 tests.
- **Demo:** emulator, driven over adb; release 0.2.x in everyday use on the owner's phone.
- **Changed decisions:** ADR-17: a priority is a fixed level of the ten-level table, the scale only chooses the levels offered, a scale change touches no task, the number is not shown (D1 rewritten; T-406's remap removed; schema 2, backup format 2). Today: header "Planned left/total", the overload banner and the Plan header of today count the done tasks against the full capacity. "Rest day" in the Plan header. Ukrainian level 8 is "Якось" everywhere.
- **New backlog items:** none; the light system navigation bar under the dark theme went into T-503.
- **Learned:** keeping the position in the scale as the stored value made every scale change lossy, a fixed table is simpler; in a drift migration `CASE WHEN cond … WHEN 1 THEN` mixes the two `CASE` forms and `WHEN 1` is always true (caught by the migration test on a temp file); `timeout` refuses to run without a console (VS Code tasks), `ping -n` is the pause; a debug build left behind by a closed debug session can show a white screen until it is restarted; `uiautomator dump` reads Flutter's semantics, so the emulator can be driven by labels instead of guessed coordinates.
### M4 — 2026-11-14
- **Done:** T-401 … T-406: Plan screen, pin from the plan, capacity of single days, ways out for at-risk tasks, Trash with a 30-day purge, priority remap for a smaller scale; 414 tests.
- **Demo:** web build in Chrome (Plan with five tasks over the days). Not on a phone yet.
- **Changed decisions:** M4 was done before the M3 device walkthrough (T-308 postponed until the app is in everyday use); priority colours are red, orange, green, teal, blue (D1); agent rules moved from `CLAUDE.md` to `AGENTS.md`.
- **New backlog items:** none.
- **Learned:** two `FloatingActionButton`s in a tab stack need their own `heroTag`; a widget field cannot be called `override`; a drift call awaited by a widget test itself needs `tester.runAsync`; a `Dismissible` that only triggers an action should return false from `confirmDismiss`.
### M2 — 2026-11-13
- **Done:** T-201 … T-206. drift schema v1 with converters, `TaskRepository` / `SettingsRepository` / `DayOverrideRepository` on drift, `DeviceSettings` in SharedPreferences, Riverpod providers up to `planProvider`, `todayProvider` with a day-start timer, SQLite wasm files for the browser; 302 tests.
- **Demo:** none on screen (the app is still the template counter); provider tests run the whole chain database → streams → plan. In Chrome the database survives a reload and a browser restart (IndexedDB).
- **Changed decisions:** ADR-13 — no debounce in `planProvider`, one task stream; every repository write takes `now` from `clockProvider`; the database file lives in the application support directory; `DeviceSettings` has its own enums (no Flutter types in the domain).
- **New backlog items:** T-301 overrides `sharedPreferencesProvider` in `main` and invalidates `todayProvider` on resume; T-308 repeats the reload check on the deployed web app.
- **Learned:** `insertOnConflictUpdate` with a row class skips null fields, use `toCompanion(false)`; drift's `dateTime()` stores seconds, so timestamps are integer milliseconds; `drift/native.dart` must stay out of `lib/` (breaks the web build); `web/drift_worker.js` and `web/sqlite3.wasm` are tied to the package versions (`tool/web_assets.dart`, guarded by a test); under `fake_async` Riverpod needs `async.elapse(Duration.zero)`, `flushMicrotasks()` is not enough.
### M1 — 2026-11-13
- **Done:** T-101 … T-110. `lib/domain` holds `LocalDate`, `Task`, `PriorityLabels`, `Settings`, `DayOverride`, `Plan`, `CapacityResolver`, `Planner`; 208 tests, planner scenarios 1–21 from [[04 Planner Algorithm]].
- **Demo:** none on screen (pure Dart); the test table is the demo. 500 tasks × 90 days plan in about 2 ms.
- **Changed decisions:** D16 — deadline-forced slots refill and an unachievable plan is highlighted on Today; ADR-11 — priority colours as ARGB ints and logical label keys; horizon counts today (≥ 1 day); `maxOverflowPerDay` 0 allowed in the domain; pins are honoured on rest days; worked example 1 corrected (the boost puts E before F on Thursday).
- **New backlog items:** at-risk banner added to T-302.
- **Learned:** freezed constructors with method-calling assertions cannot be `const`; on Windows, building from `d:\` and `D:\` (drive-letter case) wipes `windows/flutter/ephemeral` for each other, so always build from one casing (`tool/run_windows.cmd` normalises it).
### M0 — 2026-11-13
- **Done:** T-001 … T-006. CI + GitHub Pages: https://valeriyh.github.io/TasksOrder/
- **Demo:** default app runs on Windows desktop and in Chrome; debug APK builds. Phone run moved to T-308.
- **Changed decisions:** develop on Windows/web first (ADR-10); `minSdk 24`; storage is an adapter, backend left open; `json_serializable` deferred (ADR-8); `kotlin.incremental=false` (ADR-9).
- **New backlog items:** T-006 Windows & web targets, T-206 web storage setup.
- **Learned:** Flutter 3.50 moved Material widgets to `package:material_ui`; `build_runner` 2.17 dropped `--delete-conflicting-outputs`; Windows plugin builds need Developer Mode (symlinks).
