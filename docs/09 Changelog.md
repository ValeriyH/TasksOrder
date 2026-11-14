---
tags: [release, changelog]
created: 2026-11-14
---
# 09 Changelog

Versions of the app as in `version:` of `pubspec.yaml` (`name+build`). The build number grows with every APK installed over an older one (ADR-15).

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
