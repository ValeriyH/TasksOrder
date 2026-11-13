---
tags: [data-model]
created: 2026-11-12
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
| `isToday` | `bool` | Today flag (D11): in the Today queue, outside capacity, persists until done or unflagged |
| `todayFlaggedAt` | `DateTime?` (UTC) | set when `isToday` becomes true; queue tie-breaker |
| `pinnedDate` | `LocalDate?` | manual "do it on this day" for a future date (v0.2); a pin in the past behaves as today |
| `notBefore` | `LocalDate?` | reserved for snooze (later); planner ignores it in MVP |
| `status` | `TaskStatus` | `active`, `done` (D14: no "dropped"; removal is a soft delete) |
| `createdAt` | `DateTime` (UTC) | tie-breaker: older first |
| `updatedAt` | `DateTime` (UTC) | |
| `completedAt` | `DateTime?` (UTC) | set when `status == done` |
| `deletedAt` | `DateTime?` (UTC) | soft delete = Trash (D14) and sync tombstone (D12); deleted rows are filtered out of every query except Trash; purged after 30 days |

Invariants: `1 <= priority <= scale`; `completedAt != null` iff `status == done`; `todayFlaggedAt != null` iff `isToday`; `deletedAt == null` for every task the UI shows outside Trash.

Sync-readiness (D12): `id` is a UUID, every write bumps `updatedAt`, delete is soft. When accounts arrive, add `ownerId`/`assigneeId` columns with the local user as default. No other preparation is done now.

### Settings (single row)
| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `priorityScale` | `int` | 5 | allowed 3, 5, 10 |
| `weeklyCapacity` | `List<int>` (7) | `[1,1,1,1,1,3,0]` Mon..Sun | tasks per weekday, 0 = rest day |
| `maxOverflowPerDay` | `int` | 1 | extra tasks a deadline may add to a day: 1, 2 or 3 (D5) |
| `planningHorizonDays` | `int` | 90 | tasks beyond are "Later" |
| `urgencySoonDays` | `int` | 7 | due within → +1 priority level (D10) |
| `urgencyNearDays` | `int` | 2 | due within → +2 priority levels (D10) |
| `todayVisibleLimit` | `int` | 3 | how many Today-queue tasks are shown at once (D11) |
| `dayStartHour` | `int` | 0 | 0..23; "today" rolls over at this hour (D15) |

Planning settings above would sync per user in the future. **Device settings** stay local in a separate `DeviceSettings` object (SharedPreferences), so the two never mix (D12):

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `locale` | `enum` | `system` | `system` (device language, fallback en), `uk`, `en`; user-selectable (D13) |
| `themeMode` | `enum` | `system` | `system` (device light/dark), `light`, `dark`; user-selectable (D13) |
| `showReasons` | `bool` | true | badges "due / pinned / overflow" |
| `notificationTime` | `TimeOfDay?` | null | v0.2 |

### DayOverride
| Field | Type | Notes |
|-------|------|-------|
| `date` | `LocalDate` (PK) | |
| `capacity` | `int` | replaces the weekday value for this date |
| `note` | `String?` | "holiday", "trip" |

### LocalDate (value object)
Year/month/day only. Operations: `today(clock)`, `addDays`, `daysUntil`, `weekday`, `compareTo`, ISO parse/format. Never converted to `DateTime` inside the planner.

## Derived model (not persisted) — output of the planner
```dart
class Plan {
  final LocalDate today;
  final List<TodayEntry> todayQueue;  // flagged + overdue tasks in queue order (D11, D7)
  final int todayVisibleLimit;        // UI shows todayQueue.take(todayVisibleLimit); the rest is "+N more"
  final List<PlannedDay> days;        // today .. today + horizon
  final List<String> laterTaskIds;    // did not fit the horizon
  final List<String> atRiskTaskIds;   // deadline cannot be met
}

class TodayEntry {
  final String taskId;
  final bool flagged;                 // user set the Today flag
  final int overdueDays;              // 0 when not overdue; > 0 → "overdue by N days" badge
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
  is_today      INTEGER NOT NULL DEFAULT 0,
  today_flagged_at INTEGER,       -- UTC epoch ms
  pinned_date   TEXT,
  not_before    TEXT,
  status        INTEGER NOT NULL, -- 0 active, 1 done
  created_at    INTEGER NOT NULL, -- UTC epoch ms
  updated_at    INTEGER NOT NULL,
  completed_at  INTEGER,
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
  today_visible_limit         INTEGER NOT NULL DEFAULT 3,
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
Schema version 1. Migrations handled by drift `MigrationStrategy`; every schema change gets a test with the drift schema verifier.

## Repository interfaces (domain)
```dart
abstract class TaskRepository {
  Stream<List<Task>> watchAll();                 // all statuses
  Stream<List<Task>> watchActive();
  Future<Task?> getById(String id);
  Future<void> upsert(Task task);
  Future<void> complete(String id, DateTime now);
  Future<void> uncomplete(String id);
  Future<void> setToday(String id, bool value, DateTime now);
  Future<void> delete(String id);      // soft delete: sets deletedAt (Trash)
  Future<void> restore(String id);     // clears deletedAt
  Stream<List<Task>> watchTrash();
  Future<void> purgeDeleted(Duration olderThan); // housekeeping, 30 days
}
abstract class SettingsRepository {
  Stream<Settings> watch();
  Future<void> save(Settings settings);
}
abstract class DayOverrideRepository {
  Stream<Map<LocalDate, DayOverride>> watchAll();
  Future<void> upsert(DayOverride o);
  Future<void> remove(LocalDate date);
}
```

## Backup format (v0.2)
Single JSON file: `{ "version": 1, "exportedAt": ..., "settings": {...}, "tasks": [...], "dayOverrides": [...] }`. Import replaces everything after confirmation.
