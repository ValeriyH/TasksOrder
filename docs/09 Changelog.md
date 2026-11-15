---
tags: [release, changelog]
created: 2026-11-14
---
# 09 Changelog

Versions of the app as in `version:` of `pubspec.yaml` (`name+build`). The build number grows with every APK installed over an older one (ADR-15).

## 0.4.0+6 — 2026-11-15 (M7)
- **Recurring tasks** (D20, ADR-18): "Repeat" in the editor: every N days, weeks, months or years, by the calendar or counted from the day it is done, or on chosen weekdays. Completing a repeating task brings the next one; "Undo" takes it away again. Deleting asks: skip this time or delete the series.
- **The coming repeats in the Plan**, dimmed, so the load of the coming weeks is honest; a repeat that finds no day before the next one is dropped, so repeats never pile up on one day. A task that is not open yet says "From <date>".
- The database moves to schema 3 and the backup to format 3 (an older app refuses such a file instead of dropping the rules).
- **"Recurring" filter** in Tasks: only the tasks that repeat.
- **Skip this time** moves to the long-press menu of the Plan and Today (Today gets the menu too); deleting a repeating task only warns that the series stops.
- A task that repeats from the day it is done takes one completion a day: the next one says "Paused until tomorrow" until then, so a second tick cannot pile up done copies.
- Ukrainian: the due date in the editor is "Кінцевий термін".

## 0.3.1+5 — 2026-11-15
- **Home-screen widget** (T-601, ADR-22): today's tasks on the home screen with "Today · left/total"; follows every change in the app and turns to the next day by itself; a tap opens the app. Light and dark like the phone.

## 0.3.0+4 — 2026-11-14 (M5)
- **Morning notification** (T-501, ADR-20): at a time of your choice, the tasks planned for the day; on Android 13+ the app asks for the permission. Survives a restart of the phone.
- **Look** (T-503, ADR-21): new app icon (also as an Android 13 themed icon), launch screen for light and dark, the system navigation bar follows the theme of the app; Ukrainian texts reviewed (the editor title fits, the Trash note counts days correctly).
- **Tests** (T-504): an integration test of the main path runs on a device; 476 unit and widget tests.
- **Docs** (T-506): [[08 User Guide]] in English and Ukrainian ([[08 User Guide uk]]), this changelog.

## 0.2.2+3 — 2026-11-14
- Priorities are fixed levels: changing the number of levels no longer changes any task (ADR-17; database schema 2, backup format 2).
- Today: header "Planned left/total"; the overload banner counts against the full capacity. Plan: "Rest day" in the header of a day without capacity.

## 0.2.1+2 — 2026-11-14
- Backup to a file and restore from it (T-502, ADR-16).
- First release build signed with the release key (T-505, ADR-15).

## 0.2.0 — 2026-11-14
- First version on a phone: Today with Focus and quick add, Plan, Tasks with filters, the task editor, Settings, Trash; Ukrainian and English, light and dark (M3, M4).
