---
tags: [roadmap, planning]
created: 2026-11-12
---
# 05 Roadmap

Each milestone ends with a demo on a real device and a short retro: what new needs appeared → update [[01 Brainstorm]] and [[06 Task Backlog]].

| Milestone | Goal | Outcome | Tasks |
|-----------|------|---------|-------|
| **M0 — Environment & skeleton** | Toolchain works, empty app runs on Windows and in Chrome, Android APK builds | `flutter doctor` clean, project with lint, folder structure, git | T-001 … T-006 |
| **M1 — Domain core** | The planner exists and is proven by tests | `LocalDate`, `Task`, `Settings`, `Planner` (Today queue, forcing, overflow, urgency boost, pins) with the full test table from [[04 Planner Algorithm]] | T-101 … T-110 |
| **M2 — Data layer** | Tasks and settings survive restarts, streams drive a live plan | drift schema v1, repositories, device settings, `planProvider`, day-start clock | T-201 … T-205 |
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
### M0 — 2026-11-13
- **Done:** T-001 … T-006. CI + GitHub Pages: https://valeriyh.github.io/TasksOrder/
- **Demo:** default app runs on Windows desktop and in Chrome; debug APK builds. Phone run moved to T-308 (test phone on Android 7.1 needs a clean-up first).
- **Changed decisions:** develop on Windows/web first (ADR-10); `minSdk 24`; storage is an adapter, backend left open; `json_serializable` deferred (ADR-8); `kotlin.incremental=false` (ADR-9).
- **New backlog items:** T-006 Windows & web targets, T-206 web storage setup.
- **Learned:** Flutter 3.50 moved Material widgets to `package:material_ui`; `build_runner` 2.17 dropped `--delete-conflicting-outputs`; Windows plugin builds need Developer Mode (symlinks).
