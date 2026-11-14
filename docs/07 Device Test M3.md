---
tags: [testing, checklist]
created: 2026-11-13
---
# 07 Device Test M3

Manual walkthrough for T-308 in [[06 Task Backlog]]: the MVP stories from [[01 Brainstorm]] on the phone. Tick what works, write what does not under "Findings".

## Install
1. Phone: Developer options → USB debugging on, connect by USB, accept the prompt.
2. PC: `flutter build apk --debug` (built 2026-11-13: `build/app/outputs/flutter-apk/app-debug.apk`, about 190 MB as a debug build).
3. `adb install -r build/app/outputs/flutter-apk/app-debug.apk` (adb is in `%LOCALAPPDATA%\Android\Sdk\platform-tools`), or copy the file to the phone and open it.

### Emulator
When no device is at hand the walkthrough runs on an emulator: Android Emulator + image `system-images;android-36;default;x86_64` in the SDK, virtual device `TasksOrder_API36` (Pixel 6, Android 16).
- Start: `%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe -avd TasksOrder_API36`, or pick it in VS Code's device list and press F5 with "TasksOrder (Android)".
- Install a build: `adb -e install -r build/app/outputs/flutter-apk/app-debug.apk`.
- Not testable there: vibration, a real keyboard and screen, a night in the background. Android 7 (`minSdk 24`) is not covered either; an API 24 image can be added for that.

## First start
- [x] The app opens on **Today** with "Nothing planned for today" and the hint to add tasks.
- [x] Language and theme follow the phone (try the phone in Ukrainian and in English, light and dark).
- [x] The four tab labels fit the bottom bar, "Налаштування" included.

## Add a task (story: under 5 seconds)
- [x] Today → "+" → the keyboard is up and the cursor is in the title; type, press Done on the keyboard: the task is on Today. Time it.
- [x] The sheet stays above the keyboard; the "Add" button is visible.
- [x] Tasks → "+" opens the full editor: title, notes, priority "Label (n)" with a colour, due date, Focus, "Do on this day" with the "Today" shortcut.
- [x] An empty title is refused with a message.
- [x] Priority colours: red (highest), orange, green (normal), teal, blue (lowest).

## Today (stories: today's tasks and why; today stays stable)
Default capacity: Mon–Fri 1, Sat 3, Sun 0.
- [x] Add three tasks with different priorities: Today shows as many as the day's capacity, the highest priority first; the header reads "Planned n/capacity".
- [x] Tick the task: it disappears, **no other task jumps in**, the header shows "Done today: 1", a snackbar offers Undo; Undo brings it back.
- [ ] A vibration is felt on the tick.
- [x] A task with a due date of today shows "Due today" and "Deadline"; a pinned one shows "Pinned".
- [x] Tap a task: the editor opens; back returns to Today.

## Deadlines (story: warned when deadlines cannot be met)
- [x] Add three tasks due today on a day with capacity 1: two are shown (one marked "Extra"), a banner says today holds more than planned, a red banner says one task will not make its deadline.
- [x] Tap the red banner: the list of late tasks; tap one: the editor.
- [x] Tick one of the two: the third one **does** appear (deadline slots refill).

## Focus and overdue (stories: Focus, overdue never lost, ahead of time)
- [ ] Mark a task of another day as Focus (editor switch, or swipe left on Tasks): it is in the Focus section on Today with "Planned for <day>".
- [ ] Tick it in Focus: today's list does not change and there is no "Done today".
- [ ] More than three focused tasks: three shown and "+N more".
- [ ] Create a task with a due date, then set the phone's date forward past it (or wait): it shows "Overdue by N days" in Focus; its menu moves or removes the due date.

## Tasks
- [ ] All active tasks by priority, each with the day the plan gives it ("Planned for today / <day>" or "Later").
- [ ] Filters: All, Focus, With due date, Later, Done.
- [ ] Swipe right completes (with Undo), swipe left toggles Focus; the swipes do not fight with scrolling.
- [ ] Done: completed tasks under "Today" / "Yesterday" / date; unticking returns a task.
- [ ] Set the horizon to 7 days in Settings and add more tasks than a week holds: the rest are under "Later".

## Settings (story: capacity and scale)
- [ ] Change a weekday's capacity: Today and Tasks follow at once.
- [ ] Priority levels 3 / 5 / 10: the editor offers the new list.
- [ ] Language and theme switch at once, and are still there after the app is closed and opened again.
- [ ] "Show why a task is planned" off: the Pinned / Deadline / Extra badges disappear from Today.
- [ ] Day start hour, overflow, Focus size and the Advanced thresholds can be changed without errors.

## Persistence and the day
- [ ] Close the app from the recent apps list and open it: tasks and settings are still there.
- [ ] Leave the app open in the background over midnight (or over the day start hour) and come back: Today is the new day without a restart.
- [ ] Delete a task in the editor: "Moved to Trash" with Undo.

## Web (left over from T-206)
- [ ] After the next push, open https://valeriyh.github.io/TasksOrder/, add a task, reload the page: the task is still there.

## Plan, Trash and the scale (added with M4)
- [ ] Plan: every day with its tasks and `n/capacity`; "Later (N)" at the end.
- [ ] Long press on a task → "Move to a day…": the task moves and shows "Pinned"; "Unpin" lets the planner place it again.
- [ ] Tap a day header: change the capacity of that date, add a note; "As the weekday" takes it back.
- [ ] With tasks at risk: the banner opens the list; "Move due date", "One more task today" and "Delete" each make the task leave the list.
- [ ] Tasks → bin button: deleted tasks; "Restore" brings one back, "Delete forever" asks first.
- [ ] Settings → fewer priority levels: the app asks before it recalculates the priorities; Cancel changes nothing.

## Known gaps (not findings)
- No "discard changes?" question when leaving the editor.

## Findings
_Write here what went wrong: screen, steps, what you expected._

From the first days with the release APK (0.2.0) on a phone; backup and restore, the dark theme and the language worked:
- [x] The "Task completed" / "Moved to the Trash" message stayed on screen until something else happened. Cause: in this Flutter version a snackbar with an action persists by default. Fixed in 0.2.1: `undoSnackBar` in `lib/shared/task_actions_ui.dart`, gone after 4 seconds; test in `test/features/today_screen_test.dart`.
- [x] Trash: the "Restore" and "Delete forever" buttons looked alike (two bins). Fixed in 0.2.1: an arrow back for "Restore", a red bin for "Delete forever".
