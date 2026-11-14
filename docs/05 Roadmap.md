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
