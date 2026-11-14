---
tags: [guide, user]
created: 2026-11-14
---
# 08 User Guide

How to use TasksOrder 0.3. Українською: [[08 User Guide uk]]. The app takes a pile of tasks, each with a priority and an optional due date, and plans how many of them to do each day. You say how many tasks a day can hold; the app decides which ones go where. Nothing is planned by hand unless you want it to be.

## The idea in one minute
- **Tasks per day.** Settings → Planning → Tasks per day sets a number for each weekday. 0 means a rest day. This is the capacity of the day.
- **Priority.** Each task has a level: Critical, High, Normal, Low, Someday (five levels by default; three or ten in Settings). The plan fills each day with the most important tasks first; equal ones keep the order they were added in.
- **Due date.** A task with a due date gets a place on or before that day, even if that pushes a more important task later. When the deadlines need more than a day holds, the day may take a few extra tasks (Settings → Extra tasks for deadlines, +1 to +3). When even that is not enough, the task is **at risk** and a banner says so.
- **The plan follows you.** Add, complete, delete or edit a task, change a setting, or let the day pass: the plan is computed again at once. Nothing has to be moved by hand.

## Today
What to do today, in order.
- **+** adds a task: type a title, pick a priority if it is not Normal, press Add.
- The checkbox completes a task. A completed task leaves its slot empty; the next task does not slide in, so finishing the list means the day is done. "Undo" on the message brings it back.
- A tap opens the task in the editor.
- **Focus** at the top: tasks you marked to keep in sight, and overdue tasks. They are still in the plan on their own day; Focus is a second look at them.
- The header shows "Planned left/total" and how many tasks are done today.
- A banner appears when today holds more than its capacity (deadlines) or when a deadline cannot be met. A tap on the at-risk banner lists the tasks with ways out: move the due date, one more task today, delete, edit.

## Plan
The coming days, each with its tasks and "planned/capacity". A tap on a day header changes the capacity of that one day (for example a holiday or a busy day), with a note; "As the weekday" removes the change. A long press on a task pins it to a day of your choice or unpins it. Tasks that do not fit the horizon are listed under "Later".

## Tasks
All tasks with filters: All, Focus, With due date, Later, Done. The bin button opens the **Trash**: deleted tasks stay there for 30 days, can be restored or deleted forever, and leave for good after that.

## Task editor
Title, notes, priority, due date, Focus, and "Do on this day" (a pin: the task goes on that day whatever the plan would do). The bin in the top bar moves the task to the Trash.

## Home-screen widget (Android)
Long-press an empty place on the home screen → Widgets → TasksOrder, and drag the widget onto the screen; it can be resized. It shows "Today · left/total" and the tasks of the day; a day with nothing to do says so. It follows every change made in the app and turns to the next day by itself at the day start. A tap opens the app. Like the morning notification, it knows the coming days from the last time the app ran: if the app has not run for a week, the widget asks you to open it.

## Settings
- **Appearance:** language (device, Українська, English), theme (device, light, dark), the badges that say why a task is on its day (Pinned, Deadline, Extra).
- **Morning notification** (Android): switch it on, allow notifications when Android asks, tap the row to choose the time. Every day at that time a notification lists the tasks planned for the day; a tap opens the app. It can come a few minutes late (Android groups such alarms to save battery). A day with nothing planned has no notification. The texts for the coming days are prepared from the plan whenever the app runs, so open the app now and then to keep them right. A notification missed while the phone was off is shown after it starts.
- **Planning:** priority levels (3, 5 or 10), tasks per day for each weekday, extra tasks for deadlines, how far ahead to plan, how many tasks Focus shows, the hour the day starts (tasks done before it count for the day before; useful if you go to bed after midnight). Advanced: how close a due date has to be to raise the priority by one or two levels.
- **Backup:** "Save a backup" writes all tasks (the Trash too), day changes and planning settings to a file of your choice. "Restore from a backup" replaces everything in the app with the file's content, after showing what it holds and asking. Keep a backup before you reinstall the app or change phones. Language, theme and the notification are settings of the phone and are not in the backup.

## Good to know
- Everything is stored on the phone only. There is no account and no sync yet.
- The web version (https://valeriyh.github.io/TasksOrder/) keeps its own data in the browser and has no notification.
