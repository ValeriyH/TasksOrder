# TasksOrder

[![CI](https://github.com/ValeriyH/TasksOrder/actions/workflows/ci.yml/badge.svg)](https://github.com/ValeriyH/TasksOrder/actions/workflows/ci.yml) · Web build: <https://valeriyh.github.io/TasksOrder/>

Android app that takes a pile of tasks with a priority and an optional due date and plans
how many of them to do each day, based on a configurable weekly capacity.

Flutter · Riverpod · drift (SQLite) · freezed · go_router. UI in Ukrainian and English, light and dark themes.

## Documentation
Product and technical docs live in [`docs/`](docs/Home.md) (an Obsidian vault):

- [01 Brainstorm](docs/01%20Brainstorm.md): requirements and decisions D1–D15
- [02 Architecture](docs/02%20Architecture.md): layers, project structure, testing strategy
- [03 Data Model](docs/03%20Data%20Model.md)
- [04 Planner Algorithm](docs/04%20Planner%20Algorithm.md): the planner contract and its test table
- [05 Roadmap](docs/05%20Roadmap.md) and [06 Task Backlog](docs/06%20Task%20Backlog.md)

## Getting started
Requirements: Flutter stable (3.50+), JDK 17, Android SDK (platform 36). For the Windows target: Visual Studio Build Tools 2022 with "Desktop development with C++" and Windows Developer Mode (plugins need symlinks). Web runs in Chrome.

```sh
flutter pub get
tool/gen.sh            # or tool\gen.ps1 on Windows: code generation (drift, freezed, riverpod)
flutter run -d windows   # or: -d chrome, or an Android device
```

Day-to-day:

| Command | Purpose |
|---------|---------|
| `tool/gen.sh watch` | rebuild generated code on change (VS Code task "codegen: watch") |
| `dart format lib test` | formatting (CI fails on unformatted code) |
| `flutter analyze` | static analysis, must be clean |
| `flutter test` | unit and widget tests |
| `flutter build apk --debug` | debug APK |
| `dart run tool/web_assets.dart` | refresh `web/drift_worker.js` and `web/sqlite3.wasm` after upgrading `drift` or `sqlite3` |

## Project layout
```
lib/
  app/          MaterialApp, theme, router
  domain/       entities, Planner, LocalDate (pure Dart, no Flutter or drift imports)
  data/         drift database and repository implementations
  application/  Riverpod providers
  features/     screens: today, plan, tasks, task_edit, settings
  shared/       common widgets
  l10n/         ARB files (uk, en)
test/           domain, data, features
docs/           Obsidian vault
```
