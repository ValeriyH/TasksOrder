---
tags: [release, changelog]
created: 2026-11-14
---
# 09 Changelog

Versions of the app as in `version:` of `pubspec.yaml` (`name+build`). The build number grows with every APK installed over an older one (ADR-15).

## 0.7.0+14 — 2026-11-17 (M10)
- **Days** (D23, ADR-25): a task can be limited to some days of the week in the editor ("Only Thu, Fri", "Only Sat" on the card). It is planned only on those days, by priority like any task; a missed day moves it to the next one by itself, without Focus. A rest day of the set is passed over.
- With a due date the task gets one of its days before the date; on the last one it goes first ("Deadline"). After the date it is overdue and in Focus, and keeps to its days.
- A pin still wins; a pin left in the past moves to the nearest of the task's days. The task can be completed on any day. A repeating task keeps its days.
- The editor says quietly when the pin is on another day, when all the chosen days are rest days, or when none of them comes before the due date; it never blocks saving.
- Database schema 6 and backup format 6 (`allowedWeekdays`); existing tasks may be planned on any day, so the plan does not change. A backup of 0.7 cannot be read by 0.6.

## 0.6.0+13 — 2026-11-16 (M8)
- **Task size** (D21, ADR-19): Small, Normal or Large in the editor: half a slot, one or two slots of a day. Two small tasks share a slot; a large task waits for a day with room ("Waits for a day with room" on its card) while lighter tasks go ahead; a Critical large task first in line takes the next working day as an extra task. A large task never counts more than the biggest day of the week.
- The Plan counts slots ("1½/2", a half-filled dot, "½ slots free"); Today's overload banner too.
- Deadlines count sizes: a large task with a due date gets a day before its date that can hold it, or, when there is none, a working day as an extra task (within Extra tasks for deadlines).
- Database schema 5 and backup format 5 (`weight`); every existing task becomes Normal, so the plan does not change. A backup of 0.6 cannot be read by 0.5.

## 0.5.4+12 — 2026-11-16 (T-908 … T-912)
- **Postpone until…** in the task menu sets Not before (a pin before that day is removed); **Cancel postponement** while it is set. "Move to a day…" is now **Pin to a day…**.
- The task menu closes when you switch to another tab.
- Today's "All done for today" / "Nothing planned for today" is a card under Planned, in the style of the task cards.
- The pin chip says **Pinned to <date>**, except where the card already says "Planned for <date>".
- **+** on the Plan opens the editor of a new task, as on Tasks.

## 0.5.3+11 — 2026-11-16 (T-714)
- **Not before** in the task editor: the task stays off the plan until that day, then is planned by priority ("From <date>" on the card). A due date before it is refused; a pin still wins, and a pinned card no longer shows "From". On a repeating task it moves the current repeat.

## 0.5.2+10 — 2026-11-16 (T-713)
- **Taking back a completion of a repeating task** (T-713): only the last completion of a series can be taken back; in Done the Completed button of an older one is dimmed and explains. When the next repeat was changed since, the app asks and brings the task back as an ordinary one. Taking back older completions no longer leaves extra copies without the repeat.
- A series can no longer end up with two repeating tasks: a repeat set on a returned copy starts a series of its own.

## 0.5.1+8 — 2026-11-16 (T-712)
- **Repeats from completion** (T-712, ADR-24): no repeats ahead in the Plan any more, only the task itself; the next one comes when it is done (that many days later) or skipped. A skip ahead of the day counts from the day the task was meant for, so it no longer comes back on the same date. A pinned task gives a pinned next one; a due date is not repeated.

## 0.5.0+7 — 2026-11-15 (M9)
- **New look** (D22, ADR-23): the owner's design for Today, Plan and Tasks, in light and dark; the other screens take the same colours. Priorities keep their colours, made readable in both themes.
- **Task cards** with a **Done** button in place of the check box. A done task stays in sight, dimmed, with "Completed today", and **Completed** takes the completion back, so there is no "Undo" message after a completion any more.
- **A tap on a task opens its menu** (skip this time, move to a day, unpin, move or remove an overdue due date, edit) on Today, Plan and Tasks; no long press.
- **Today**: the date, a progress bar of today's list ("2 of 3"), sections Focus (with the number of tasks in Focus) and Planned (done/total); tasks done today stay at the end of their section until the day ends.
- **Plan**: the range of days at the top, a pill with a dot per place of each day ("planned/capacity", red when over), a button to change the capacity of a day, "· rest day", and a dashed box with the free places. A task done ahead stays at the end of the day it was planned for until that day is over, and its place goes to the next task (T-907).
- **Tasks**: "N active" at the top; the filter **Active** (was All) and every filter with its number of tasks, Done last; a task completed here stays in the list until you choose another filter or leave the tab.
- The database moves to schema 4 and the backup to format 4: a completion remembers the day it was planned for (an older app refuses such a file).
- The launch screen takes the new background colours.

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
