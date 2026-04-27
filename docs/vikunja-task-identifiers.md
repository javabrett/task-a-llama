# Vikunja task identifier archaeology

Research into the history and stability of Vikunja's two task identifier
systems. Conducted 2026-04-26 against the Vikunja source checkout at
`repos/vikunja/`.

## Two identifiers

Vikunja exposes two identifiers per task:

| Identifier | Field | Example | Stable? |
|---|---|---|---|
| Global ID | `task.id` | `17` | Yes - DB primary key, never changes |
| Project index | `task.index` | `TAL-1` or `#1` | No - can be reassigned |

**Always use the global `id` in API calls, URLs, and integrations.**

## History of the project index feature

The project identifier + task index feature did not ship with the original
Vikunja codebase. Key timeline:

- **Dec 7, 2019** - PR #115 (commit `720df3cbe`): initial feature lands.
  Adds `Identifier` varchar(10) to the list (later: project) table and
  `Index` int64 to the tasks table. Migrations `20191207204427` and
  `20191207220736`. Existing tasks were backfilled with sequential indices
  ordered by task ID.

- **May 2020** - commit `5a86f44fc`: auto-generation of identifiers from
  the project title added.

- **Jun 11, 2020** - commit `e2fb50c39`: "Show task index instead of id on
  kanban" - the global task ID was previously displayed on the Kanban board;
  this commit explicitly replaced it with the per-project index. So there
  was a ~6-month window where the stable global ID was the primary display
  reference.

- **Dec 18, 2020** - commit `ccfa01987`: "Don't create a list identifier by
  default" - auto-generation disabled. From this point the identifier is
  opt-in: you must manually set it in project settings. Most projects show
  no prefix (display as `#42` not `PROJ-42`).

- **Nov 2022** - large refactor renames "list" model to "project" throughout.

- **Apr 2026** - commits `0c3d01099`, `9206f98d6`: ongoing fixes to task
  position conflict detection and unique constraint enforcement. Suggests
  index/position stability continues to need attention.

## Why the project index is not a stable reference

The index is calculated as `MAX(current task indices in project) + 1`
(`calculateNextTaskIndex`, `pkg/models/tasks.go:860`):

```go
func calculateNextTaskIndex(s *xorm.Session, projectID int64) (nextIndex int64, err error) {
    latestTask := &Task{}
    _, err = s.Where("project_id = ?", projectID).
        OrderBy("`index` desc").
        Get(latestTask)
    return latestTask.Index + 1, nil
}
```

Consequences observed live (2026-04-26, test stack):

1. "test task" created in TAL project -> receives `index = 1` (TAL-1)
2. "test task" moved to Other Stuff -> TAL project now empty, MAX = 0
3. "test2" created in TAL -> receives `index = MAX(0) + 1 = 1` -> becomes TAL-1
4. "test task" moved back to TAL -> receives `index = MAX(1) + 1 = 2` -> becomes TAL-2

"test task" (global id 1) started as TAL-1 and ended as TAL-2. The identifier
TAL-1 now permanently belongs to a different task (global id 2, "test2").

There is also a historical bugfix commit specifically titled "fix: make sure
task indexes are calculated correctly when moving tasks between lists",
confirming that move-triggered index behaviour has been a known source of bugs.

## The proposed by-ref endpoint (vikunja#2694)

A `GET /tasks/by-ref/TAL-1` endpoint has been proposed to allow looking up
tasks by their project-scoped identifier. Given the index reuse behaviour
above, this endpoint would be inherently unsafe as a durable reference
without additional safeguards - a caller could silently receive the wrong
task if the project was modified in between.

No reference to this proposal was found in the Vikunja commit log as of
the archaeology date.

## Implications for task-a-llama

- The `/tal` skill uses and emits only global `id` values and full task URLs
  (`/tasks/{id}`). Project-index display labels are treated as read-only UI
  annotations.
- CLAUDE.md "Task ID system" section carries a strong warning and the source
  citation for `calculateNextTaskIndex`.
- `docs/task-model.md` carries the same warning with the live observation
  sequence documented.
