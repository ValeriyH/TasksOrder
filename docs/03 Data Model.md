---
tags: [data-model]
created: 2026-11-12
updated: 2026-11-14
---
# 03 Data Model

## Domain entities (pure Dart, `freezed`)

### Task
| Field | Type | Notes |
|-------|------|-------|
| `id` | `String` (UUID v4) | |
| `title` | `String` | required, trimmed, non-empty |
| `notes` | `String?` | |
| `priority` | `int` | a level of the ten-level table: 1 = highest … 10 = lowest, Normal = 5, whatever the scale (D1, ADR-17). Shown as its name only; a level the scale does not offer reads as the nearest one. Table in [[01 Brainstorm]] |
| `weight` | `int` | size of the task in **half-slots** of the daily capacity (D21, ADR-19; planned, T-801, schema 5): 1 = small, 2 = normal (default), 4 = large. `TaskSize` names these three for the UI; any other value ≥ 1 is valid and reads as the nearest size. The planner uses `effWeight`, see [[04 Planner Algorithm]] |
| `dueDate` | `LocalDate?` | calendar day, no time |
| `isFocused` | `bool` | Focus mark (D17): kept in sight in the Focus view; the task is planned like any other. Persists until done or unmarked |
| `focusedAt` | `DateTime?` (UTC) | set when `isFocused` becomes true; Focus tie-breaker |
| `pinnedDate` | `LocalDate?` | manual "do it on this day"; placed whatever the capacity; a pin in the past behaves as today |
| `notBefore` | `LocalDate?` | release date: the planner does not place the task before this day (T-703; ignored until then). Set by the app for the next instance of a series (D20); a field to set it by hand (snooze) is not built. A pin beats it |
| `recurrence` | `Recurrence?` | repeat rule (D20, schema 3); `null` = an ordinary task. The same for every instance of a series |
| `seriesId` | `String?` | id of the first task of the series; ties the done instances, the active one and the Trash together. Stays when the rule is removed |
| `occurrenceDate` | `LocalDate?` | the date of this instance in its series. Set with the rule; a one-off move of the pin or the due date does not change it, so the schedule does not shift |
| `status` | `TaskStatus` | `active`, `done` (D14: no "dropped"; removal is a soft delete) |
| `createdAt` | `DateTime` (UTC) | tie-breaker: older first |
| `updatedAt` | `DateTime` (UTC) | |
| `completedAt` | `DateTime?` (UTC) | set when `status == done` |
| `completedOnPlan` | `bool` | set at completion: the task was on today's list of the plan at that moment (D19). Only such completions lower that day's capacity. False while active |
| `completedPlanDate` | `LocalDate?` | set at completion: the day the plan had the task on at that moment (T-907, D22, schema 4); null for a task the plan had not placed (Later) and for completions stored before schema 4. The Plan keeps the done task at the end of that day until the day is past (`Planner.keptOnDay`); the day's slot is planned again. Not a capacity input: D19 still counts only `completedOnPlan`. Cleared by uncomplete |
| `deletedAt` | `DateTime?` (UTC) | soft delete = Trash (D14) and sync tombstone (D12); deleted rows are filtered out of every query except Trash; purged after 30 days |

Invariants: `1 <= priority <= scale`; `completedAt != null` iff `status == done`; `focusedAt != null` iff `isFocused`; `completedOnPlan` and `completedPlanDate` only when `status == done`; `deletedAt == null` for every task the UI shows outside Trash. With D20: `recurrence != null` implies `seriesId != null` and `occurrenceDate != null`; a series has at most one instance that is active, not deleted and carries a rule (kept by the repository, not by `Task`). With D21: `weight >= 1`; the successor of a recurring task copies it.

### Recurrence (value object, D20, T-701)
Two kinds, a sealed class in `lib/domain/model/recurrence.dart` (`IntervalRecurrence`, `WeekdaysRecurrence`; not `freezed`, so the factories refuse a broken rule with `ArgumentError` also in a release build, where assertions are off):

| Kind | Fields | Meaning |
|------|--------|---------|
| `interval` | `every` (int ≥ 1), `unit` (`day`, `week`, `month`, `year`), `afterDone` (bool), `anchor` (`LocalDate`, only when `afterDone` is false) | every N units. **By schedule** (`afterDone == false`): the dates are `anchor + k × every` units, each computed from the anchor, so "monthly, anchor Jan 31" gives Feb 28 (29), Mar 31, Apr 30. **From completion** (`afterDone == true`): the next date is the day of completion + `every` units |
| `weekdays` | `days` (non-empty set of 0..6, Monday = 0 as in `LocalDate.weekday`) | every listed weekday; always by schedule |

Stored as JSON text, the same in the database column and in the backup:
```json
{"kind":"interval","every":1,"unit":"month","afterDone":false,"anchor":"2026-11-30"}
{"kind":"interval","every":30,"unit":"day","afterDone":true}
{"kind":"weekdays","days":[0,2,4]}
```

Rules of a series (`Task.successor`, T-702):
- **Start.** Setting a rule in the editor gives the task `seriesId` (its own id when it had none) and `occurrenceDate = pinnedDate ?? dueDate ?? notBefore ?? today`; an interval rule by schedule takes that date as `anchor`. Saving the editor with another pin or due date moves `occurrenceDate` and `anchor` with it (the user changed the schedule). The quick actions (move due date, move to a day, unpin) leave them alone: a one-off move.
- **Next date** when the instance is completed or skipped on the day `today`: from completion → `today + every` units; by schedule → the first date of the rule after `max(today, occurrenceDate)`. So missed repeats are dropped, and an instance done ahead of its day does not produce a second one for the same date.
- **One completion a day from completion (T-710):** an active instance whose rule counts from completion cannot be completed on a planning day (D15) on which another task of its series was completed: done again the same day it would bring the same next date (done on the 15th, every 10 days: the 25th, again and again). It is paused until the next day (derived, nothing stored: `Planner.pausedToday`; `TaskActions.complete` refuses it; the tile shows "Paused until tomorrow" and a tick explains). Undo of the completion lifts it. Rules by the calendar are not paused: the next one done ahead moves the series on (a rent paid for two months).
- **Successor** = a new active task: the same `title`, `notes`, `priority`, `recurrence`, `seriesId`; `occurrenceDate` = the next date; no Focus mark; `createdAt = now`. Its id is a version 5 UUID of the name `next/<predecessor id>` in a fixed namespace of the app (`Task.successorId`): the same on every device (D12) and known to undo. (A namespace of its own instead of the predecessor's id as the namespace: an id need not be a UUID, as in tests.)
- **Where the date goes** follows the dates the predecessor has:

  | Predecessor has | Successor gets | Planned as |
  |-----------------|----------------|------------|
  | `pinnedDate` | `pinnedDate` = next date; a `dueDate` keeps its distance from the pin | exactly on that day (the pin leads, as for any task) |
  | `dueDate` only | `dueDate` = next date, `notBefore` = the day after the predecessor's `occurrenceDate` (for `afterDone`: after the day of completion) | by priority and deadline inside its own period |
  | neither | `notBefore` = next date | available from that day, then by priority |

- **Complete**: the repository marks the instance done and inserts the successor in one transaction, unless the series already has another active instance.
- **Undo** (`uncomplete`): the successor is removed for good when it is still active and untouched (`updatedAt == createdAt`); otherwise the task that returns loses its rule and stays as an ordinary task of the series.
- **Skip** ("not this time", from the long-press menu of the Plan and Today, T-711): the instance goes to the Trash and the successor is inserted, as on completion.
- **Delete the series** (Delete in the editor, after a warning that the series stops): the instance goes to the Trash with its rule and no successor. Restoring it resumes the series. Restoring a skipped instance first removes the successor its skip made when that one is still untouched (so "Undo" of a skip puts everything back); when the series still has another active instance, the restored one comes back without the rule.
- **Stop repeating**: "Repeat: none" in the editor clears `recurrence` and `occurrenceDate`; the task stays as an ordinary one.

Sync-readiness (D12): `id` is a UUID, every write bumps `updatedAt`, delete is soft. When accounts arrive, add `ownerId`/`assigneeId` columns with the local user as default. No other preparation is done now.

### Settings (single row)
| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `priorityScale` | `int` | 5 | allowed 3, 5, 10: which levels the app offers (3 → Critical, Normal, Low; 5 adds High, Someday; 10 all); tasks keep their levels when it changes |
| `weeklyCapacity` | `List<int>` (7) | `[1,1,1,1,1,3,0]` Mon..Sun | tasks per weekday, 0 = rest day |
| `maxOverflowPerDay` | `int` | 1 | extra tasks a deadline may add to a day: 1, 2 or 3 in the UI (D5); the domain also accepts 0 = no overflow |
| `planningHorizonDays` | `int` | 90 | number of planned days including today (≥ 1); tasks beyond are "Later" |
| `urgencySoonDays` | `int` | 7 | due within → +1 priority level (D10) |
| `urgencyNearDays` | `int` | 2 | due within → +2 priority levels (D10) |
| `focusVisibleLimit` | `int` | 3 | how many tasks the Focus strip shows at once (D17) |
| `dayStartHour` | `int` | 0 | 0..23; "today" rolls over at this hour (D15) |

Planning settings above would sync per user in the future. **Device settings** stay local in a separate `DeviceSettings` object (SharedPreferences), so the two never mix (D12):

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `locale` | `AppLocale` | `system` | `system` (device language, fallback en), `uk`, `en`; user-selectable (D13) |
| `themeMode` | `AppThemeMode` | `system` | `system` (device light/dark), `light`, `dark`; user-selectable (D13) |
| `showReasons` | `bool` | true | badges "due / pinned / overflow" |
| `notificationTime` | `int?` | null | morning notification: minutes after midnight, local time; null = off (T-501, ADR-20). Stored as `device.notificationTime`; a value outside 0..1439 reads as off |

### Home-screen widget cache (T-601, ADR-22)
Not a store of the plan: a copy the Android widget reads because it cannot compute the plan (D2). Written by the app on every change of the plan to the SharedPreferences file `today_widget`, key `cache`, as JSON:

```json
{
  "format": 1,
  "dayStartHour": 0,
  "stale": "Open TasksOrder to update the plan",
  "days": [
    {"date": "2026-11-15", "header": "Today · 2/3", "lines": ["Call mom", "Pay bills"], "empty": null},
    {"date": "2026-11-16", "header": "Today", "lines": [], "empty": "Rest day"}
  ]
}
```

Seven days from today. Texts are in the app's language. `lines` holds at most 8 entries, the last one "+N more" when there are more tasks; `empty` is set only when `lines` is empty ("All done for today", "Rest day" or "Nothing planned for today"). The widget shows the entry whose `date` is the current plan day and `stale` when there is none. A change of the format raises `format`.

### DayOverride
| Field | Type | Notes |
|-------|------|-------|
| `date` | `LocalDate` (PK) | |
| `capacity` | `int` | replaces the weekday value for this date |
| `note` | `String?` | "holiday", "trip" |

### LocalDate (value object)
Year/month/day only. Operations: `todayFor(now, dayStartHour)`, `addDays`, `daysUntil`, `weekday`, `compareTo`, ISO parse/format; with T-701 also `addMonths` and `addYears`, which keep the day of the month and fall back to the last day of a shorter month. Never converted to `DateTime` inside the planner.

## Derived model (not persisted) — output of the planner
```dart
class Plan {
  final LocalDate today;
  final List<FocusEntry> focus;       // focused + overdue tasks in focus order (D17, D18); a view over days/later
  final int focusVisibleLimit;
  final List<PlannedDay> days;        // today .. today + horizon - 1
  final List<String> laterTaskIds;    // did not fit the horizon
  final List<String> atRiskTaskIds;   // deadline cannot be met
  List<FocusEntry> get visibleFocus;  // Focus strip: entries not on today's list, first focusVisibleLimit
  int get hiddenFocusCount;           // "+N more"
}

class FocusEntry {
  final String taskId;
  final bool focused;                 // user set the Focus mark
  final int overdueDays;              // 0 when not overdue; > 0 → "overdue by N days" badge
  final LocalDate? plannedDate;       // day the plan puts it on; null = later
}

class PlannedDay {
  final LocalDate date;
  final int capacity;                 // effective (override ?? weekday)
  final List<PlanEntry> entries;
  bool get isOverloaded => entries.length > capacity;
}

class PlanEntry {
  final String taskId;
  final PlanReason reason;            // pinned | deadline | priority
  final bool overflow;                // placed above capacity
  final bool atRisk;                  // placed after its due date
  final LocalDate? occurrenceDate;    // T-704: null = the stored task; set = a ghost, the repeat of
                                      // task `taskId` for that date (D20). Identity: (taskId, occurrenceDate)
  bool get isGhost => occurrenceDate != null;
}
```
Ghosts (D20) appear only in `days[1..]`: never today, never in `focus`, `laterTaskIds` or `atRiskTaskIds`. They count in `entries.length`, so `n/capacity` and `isOverloaded` include them.

Planned with T-802 (D21): `PlanEntry.weight` (the `effWeight` the planner used, in half-slots) and `PlanEntry.waitsForRoom` (the task was skipped on an earlier day only because it did not fit what was left of it); `PlannedDay.load` = the sum of the weights of its entries, and `isOverloaded` becomes `load > 2 × capacity`. The UI shows the load in slots ("1½ / 2").

## Persistence schema (drift / SQLite)
```sql
CREATE TABLE tasks (
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  notes         TEXT,
  priority      INTEGER NOT NULL,
  due_date      TEXT,             -- 'yyyy-MM-dd' or NULL
  is_focused    INTEGER NOT NULL DEFAULT 0,
  focused_at    INTEGER,          -- UTC epoch ms
  pinned_date   TEXT,
  not_before    TEXT,
  recurrence    TEXT,             -- schema 3: JSON repeat rule or NULL (D20)
  series_id     TEXT,             -- schema 3: id of the first task of the series
  occurrence_date TEXT,           -- schema 3: 'yyyy-MM-dd', date of this instance in the series
  status        INTEGER NOT NULL, -- 0 active, 1 done
  created_at    INTEGER NOT NULL, -- UTC epoch ms
  updated_at    INTEGER NOT NULL,
  completed_at  INTEGER,
  completed_on_plan INTEGER NOT NULL DEFAULT 0, -- D19
  completed_plan_date TEXT,              -- 'yyyy-MM-dd'; schema 4, T-907
  deleted_at    INTEGER           -- soft delete (D12)
);
CREATE INDEX idx_tasks_status ON tasks(status, deleted_at);
CREATE INDEX idx_tasks_due ON tasks(due_date);
CREATE INDEX idx_tasks_series ON tasks(series_id);   -- schema 3

CREATE TABLE settings (
  id                          INTEGER PRIMARY KEY CHECK (id = 1),
  priority_scale              INTEGER NOT NULL DEFAULT 5,
  weekly_capacity             TEXT NOT NULL DEFAULT '[1,1,1,1,1,3,0]', -- JSON array Mon..Sun
  max_overflow_per_day        INTEGER NOT NULL DEFAULT 1,
  planning_horizon_days       INTEGER NOT NULL DEFAULT 90,
  urgency_soon_days           INTEGER NOT NULL DEFAULT 7,
  urgency_near_days           INTEGER NOT NULL DEFAULT 2,
  focus_visible_limit         INTEGER NOT NULL DEFAULT 3,
  day_start_hour              INTEGER NOT NULL DEFAULT 0,
  updated_at                  INTEGER NOT NULL
);

CREATE TABLE day_overrides (
  date        TEXT PRIMARY KEY,   -- 'yyyy-MM-dd'
  capacity    INTEGER NOT NULL,
  note        TEXT,
  updated_at  INTEGER NOT NULL,
  deleted_at  INTEGER
);
```
The code is at schema version 4 (snapshots: `drift_schemas/drift_schema_v1.json` … `drift_schema_v4.json`; v1 and v2 have the same tables). Migrations are handled by drift `MigrationStrategy` and tested in `test/data/database_schema_test.dart` with drift's `SchemaVerifier` on the helpers in `test/data/generated_migrations/`. After a schema change: `dart run drift_dev schema dump lib/data/db/database.dart drift_schemas/`, then `dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/`.
- 1 → 2 (ADR-17): `tasks.priority` was the position in the scale of the settings, `1..priority_scale`; it becomes the level at that position (`PriorityLabels.fromPosition`): scale 5 → 2, 3, 5, 7, 8; scale 3 → 2, 5, 7; scale 10 unchanged. A value past either end becomes that end. `updated_at` stays.
- 2 → 3 (D20, ADR-18; T-705): three nullable columns on `tasks` (`recurrence`, `series_id`, `occurrence_date`) and the index `idx_tasks_series`. No row changes: every existing task is an ordinary one. `not_before` is in the table since schema 1 and only starts to be used. New snapshot `drift_schema_v3.json`.
- 3 → 4 (T-907, D22, ADR-23): `tasks.completed_plan_date TEXT` (nullable). No row changes: a completion stored before does not know its plan day, and one from today's list still shows on the day it was done (`completedOnPlan`). New snapshot `drift_schema_v4.json`.
- 4 → 5 (D21, ADR-19; planned, T-804): `tasks.weight INTEGER NOT NULL DEFAULT 2`. Every existing task becomes a normal one, so the plan does not change. New snapshot `drift_schema_v5.json`. (Planned as 3 → 4; M9 came first, owner 2026-11-15.)

The `settings` row is seeded when the database is created, with the column defaults and `updated_at = 0`: the epoch marks a row the user never changed, so it loses any last-write-wins merge. Drift row classes are named `TaskRow`, `SettingsRow`, `DayOverrideRow`; they stay inside `lib/data`.

## Repository interfaces (domain)
```dart
// Every write takes `now` and stamps it on updatedAt; an unknown id is ignored.
abstract interface class TaskRepository {
  Stream<List<Task>> watchAll();                 // active + done, no Trash; oldest first
  Stream<List<Task>> watchActive();              // oldest first
  Stream<List<Task>> watchTrash();               // latest deletion first
  Future<Task?> getById(String id);              // also finds a task in the Trash
  Future<void> upsert(Task task, DateTime now);
  Future<void> complete(String id, DateTime now, {required bool onPlan}); // D19
  Future<void> uncomplete(String id, DateTime now);
  Future<void> setFocus(String id, bool value, DateTime now);
  Future<void> delete(String id, DateTime now);  // soft delete: sets deletedAt (Trash)
  Future<void> restore(String id, DateTime now); // clears deletedAt
  Future<void> deleteForever(String id);         // "Delete forever" in the Trash
  Future<int> purgeDeleted(Duration olderThan, DateTime now); // housekeeping, 30 days
  // Planned with T-705 (D20):
  // - complete() and the new skip() also take `required LocalDate today` and insert the
  //   successor of a recurring task in the same transaction;
  // - skip(id, now, today: ...) moves the instance to the Trash and inserts the successor;
  // - uncomplete() removes an untouched successor; restore() drops the rule when the
  //   series has another active instance.
}
abstract interface class SettingsRepository {
  Stream<Settings> watch();                      // defaults when nothing is stored
  Future<void> save(Settings settings, DateTime now);
}
abstract interface class DayOverrideRepository {
  Stream<Map<LocalDate, DayOverride>> watchAll();
  Future<void> upsert(DayOverride override, DateTime now);
  Future<void> remove(LocalDate date, DateTime now); // soft delete
}
abstract interface class DeviceSettingsRepository { // SharedPreferences, never syncs
  DeviceSettings load();                         // defaults for anything missing
  Future<void> save(DeviceSettings settings);
}
```

## Backup format (version 2)
One JSON file, `tasksorder-backup-<yyyy-MM-dd>.json`, written and read by `BackupCodec` (ADR-16 in [[02 Architecture]]):
```json
{
  "app": "TasksOrder",
  "version": 2,
  "exportedAt": "2026-11-14T00:28:44.345Z",
  "settings": { "priorityScale": 5, "weeklyCapacity": [1,1,1,1,1,3,0], "maxOverflowPerDay": 1,
                "planningHorizonDays": 90, "urgencySoonDays": 7, "urgencyNearDays": 2,
                "focusVisibleLimit": 3, "dayStartHour": 0 },
  "tasks": [ { "id": "…", "title": "…", "priority": 5, "isFocused": false, "status": "active",
               "createdAt": "…", "updatedAt": "…", "completedOnPlan": false } ],
  "dayOverrides": [ { "date": "2026-12-25", "capacity": 0, "note": "holiday" } ]
}
```
- Task fields are those of the `Task` table above; a field without a value (`notes`, `dueDate`, `focusedAt`, `pinnedDate`, `notBefore`, `completedAt`, `deletedAt`) is left out. `status` is `active` or `done`.
- Instants are ISO-8601 UTC text, calendar days `yyyy-MM-dd`.
- `tasks` holds the Trash too (`deletedAt`); `dayOverrides` only the ones in force. Device settings are not in the file.
- `priority` is the level 1..10 (ADR-17). In version 1 it was the position in the file's `priorityScale`; such a file is still read, each priority turned into the level at that position, as the schema migration does.
- Reading checks the invariants of `Task` and `Settings`; a file that breaks them, or with `version` above 2, is refused and nothing changes. A priority outside 1..10 (or outside the scale of a version 1 file) is moved to the nearest end. Unknown fields are ignored.
- Restore replaces everything after a confirmation (`BackupRepository.replaceAll`, one transaction). Tasks keep their timestamps.
- **Version 3 (T-706, D20):** a task may also carry `recurrence` (the JSON object shown under Recurrence), `seriesId` and `occurrenceDate`; all three are left out for an ordinary task. Reading checks the rule (`every ≥ 1`, a known `unit`, `anchor` exactly when `afterDone` is false, `days` non-empty within 0..6), that a rule comes with `seriesId` and `occurrenceDate`, and that no series has two active instances with a rule outside the Trash. Files of version 1 and 2 are read as before. The version goes up because an older app ignores unknown fields and would silently drop the rules; with 3 it refuses the file.
- **Version 4 (T-907, D22):** a done task may carry `completedPlanDate`; it is left out when there is none, and a file of version 1–3 reads with none. On an active task it is refused. The version goes up for the same reason as with 3.
- **Version 5 (planned, T-804, D21):** a task may carry `weight` (half-slots, ≥ 1); it is left out for a normal task (2), and a file of version 1–4 reads with 2 everywhere. A weight below 1 is refused. The version goes up for the same reason as with 3.

```dart
abstract interface class BackupRepository {
  Future<Backup> read(DateTime now);                     // everything, the Trash too
  Future<void> replaceAll(Backup backup, DateTime now);  // all or nothing
}
abstract interface class BackupFileStore {               // system file dialogs
  Future<bool> save(String fileName, String content);    // false = cancelled
  Future<String?> pick();                                // null = cancelled
}
```
