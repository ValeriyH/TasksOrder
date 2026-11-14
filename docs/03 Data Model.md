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
| `priority` | `int` | 1 = highest … `settings.priorityScale` = lowest (D1). Shown as "Label (n)"; label tables per scale in [[01 Brainstorm]] |
| `dueDate` | `LocalDate?` | calendar day, no time |
| `isFocused` | `bool` | Focus mark (D17): kept in sight in the Focus view; the task is planned like any other. Persists until done or unmarked |
| `focusedAt` | `DateTime?` (UTC) | set when `isFocused` becomes true; Focus tie-breaker |
| `pinnedDate` | `LocalDate?` | manual "do it on this day"; placed whatever the capacity; a pin in the past behaves as today |
| `notBefore` | `LocalDate?` | reserved for snooze (later); planner ignores it in MVP |
| `status` | `TaskStatus` | `active`, `done` (D14: no "dropped"; removal is a soft delete) |
| `createdAt` | `DateTime` (UTC) | tie-breaker: older first |
| `updatedAt` | `DateTime` (UTC) | |
| `completedAt` | `DateTime?` (UTC) | set when `status == done` |
| `completedOnPlan` | `bool` | set at completion: the task was on today's list of the plan at that moment (D19). Only such completions lower that day's capacity. False while active |
| `deletedAt` | `DateTime?` (UTC) | soft delete = Trash (D14) and sync tombstone (D12); deleted rows are filtered out of every query except Trash; purged after 30 days |

Invariants: `1 <= priority <= scale`; `completedAt != null` iff `status == done`; `focusedAt != null` iff `isFocused`; `completedOnPlan` only when `status == done`; `deletedAt == null` for every task the UI shows outside Trash.

Sync-readiness (D12): `id` is a UUID, every write bumps `updatedAt`, delete is soft. When accounts arrive, add `ownerId`/`assigneeId` columns with the local user as default. No other preparation is done now.

### Settings (single row)
| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `priorityScale` | `int` | 5 | allowed 3, 5, 10 |
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
| `notificationTime` | `TimeOfDay?` | null | v0.2 |

### DayOverride
| Field | Type | Notes |
|-------|------|-------|
| `date` | `LocalDate` (PK) | |
| `capacity` | `int` | replaces the weekday value for this date |
| `note` | `String?` | "holiday", "trip" |

### LocalDate (value object)
Year/month/day only. Operations: `todayFor(now, dayStartHour)`, `addDays`, `daysUntil`, `weekday`, `compareTo`, ISO parse/format. Never converted to `DateTime` inside the planner.

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
}
```

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
  status        INTEGER NOT NULL, -- 0 active, 1 done
  created_at    INTEGER NOT NULL, -- UTC epoch ms
  updated_at    INTEGER NOT NULL,
  completed_at  INTEGER,
  completed_on_plan INTEGER NOT NULL DEFAULT 0, -- D19
  deleted_at    INTEGER           -- soft delete (D12)
);
CREATE INDEX idx_tasks_status ON tasks(status, deleted_at);
CREATE INDEX idx_tasks_due ON tasks(due_date);

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
Schema version 1 (snapshot: `drift_schemas/drift_schema_v1.json`). Migrations handled by drift `MigrationStrategy`; every schema change gets a test with the drift schema verifier.

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
  Future<int> remapPriorities(int Function(int priority) remap, DateTime now); // smaller scale (T-406)
  Future<int> purgeDeleted(Duration olderThan, DateTime now); // housekeeping, 30 days
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

## Backup format (version 1)
One JSON file, `tasksorder-backup-<yyyy-MM-dd>.json`, written and read by `BackupCodec` (ADR-16 in [[02 Architecture]]):
```json
{
  "app": "TasksOrder",
  "version": 1,
  "exportedAt": "2026-11-14T00:28:44.345Z",
  "settings": { "priorityScale": 5, "weeklyCapacity": [1,1,1,1,1,3,0], "maxOverflowPerDay": 1,
                "planningHorizonDays": 90, "urgencySoonDays": 7, "urgencyNearDays": 2,
                "focusVisibleLimit": 3, "dayStartHour": 0 },
  "tasks": [ { "id": "…", "title": "…", "priority": 3, "isFocused": false, "status": "active",
               "createdAt": "…", "updatedAt": "…", "completedOnPlan": false } ],
  "dayOverrides": [ { "date": "2026-12-25", "capacity": 0, "note": "holiday" } ]
}
```
- Task fields are those of the `Task` table above; a field without a value (`notes`, `dueDate`, `focusedAt`, `pinnedDate`, `notBefore`, `completedAt`, `deletedAt`) is left out. `status` is `active` or `done`.
- Instants are ISO-8601 UTC text, calendar days `yyyy-MM-dd`.
- `tasks` holds the Trash too (`deletedAt`); `dayOverrides` only the ones in force. Device settings are not in the file.
- Reading checks the invariants of `Task` and `Settings`; a file that breaks them, or with `version` above 1, is refused and nothing changes. A priority outside the scale of the file is moved to the nearest end. Unknown fields are ignored.
- Restore replaces everything after a confirmation (`BackupRepository.replaceAll`, one transaction). Tasks keep their timestamps.

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
