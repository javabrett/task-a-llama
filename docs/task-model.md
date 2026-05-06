# Task Data Model Mapping

How Claude Code's notion of a TODO maps onto Vikunja's richer task model.
This is a design document - it informs the `/tal` skill that Phase 2 will
build, but does not by itself change any code in the framework repo.

## Reading order

1. Skim [design-decisions.md](design-decisions.md) if you haven't - this
   document assumes the four-repo split and single-user framing.
2. Read this document end-to-end. The mapping choices here are proposals;
   the marked open questions want deliberate answers before the skill is
   implemented.
3. The authoritative Vikunja source is checked out at `repos/vikunja/`
   (gitignored). File references below point at that checkout.

## What Claude Code brings to the table

Tasks come from inside an engineering workflow:

- Freeform, often one-liners scraped from a larger conversation
  ("follow up on ingestion config", "draft security response")
- Usually captured in bulk, three-to-ten at a time
- Tied to the *current working directory* - the user is mid-task in a
  specific repo, for a specific customer, when they say "capture these"
- Rarely due-dated or priority-tagged at capture time - that's
  loop-update work done in the web UI

Claude Code lacks native per-task persistence beyond in-session `MEMORY.md`
and project `CLAUDE.md` files. Without a durable backend, TODOs get lost
between sessions. `task-a-llama` supplies the backend.

## What Vikunja offers

Grounded in source (`repos/vikunja/pkg/models/`):

- **Task** (`tasks.go`): title (required), description, done, due_date,
  start_date, end_date, priority (int64, loosely 0-5), repeat_after,
  percent_done, hex_color, project_id (required). Labels, assignees,
  reminders, and attachments are separate endpoints, attached after
  task creation.
- **Project** (`project.go`): hierarchical via `parent_project_id`.
  Optional short `identifier` (<= 10 chars) used in task keys like
  `PROJ-#123`. Numeric `id` is the canonical handle.
- **Label** (`label.go`): global per user, not scoped to a project.
  Many-to-many with tasks.
- **Priority**: no fixed enum, but the Vikunja UI treats 0 as unset and
  1-5 as increasing priority.
- **Filter language** (`task_collection_filter.go`): supports `&&`, `||`,
  `=`, `!=`, `>`, `>=`, `<`, `<=`, `~`, `in`, and datemath (`now-7d`).
  Filterable fields include `done`, `priority`, `due_date`, `labels`,
  `project_id`, `assignees`.

Subtasks exist via `RelatedTasks` with kind `subtask`/`parenttask` but
are managed through `/api/v1/tasks/{id}/relations`, not on the task
object itself.

## Task identifiers - stability warning

Vikunja exposes two identifiers per task:

- **Global `id`** (`task.id`) - the database primary key. Stable, unique
  across all projects, used in all API calls and URLs (e.g. `/tasks/17`).
  This is the only identifier the skill uses or that callers should rely on.

- **Project index** (`task.index`) - a per-project sequential counter
  displayed in the UI as `#10`, or as `TAL-10` when the project has an
  `identifier` prefix set. **This is NOT a stable reference.**

The index is assigned as `MAX(current task indices in project) + 1`
(source: `calculateNextTaskIndex` in
`repos/vikunja/pkg/models/tasks.go:860`). Consequences:

- When a task moves to a different project it gets a new `MAX + 1` index
  in the destination. Its old index slot in the source is now free.
- When all tasks leave a project, `MAX = 0`, so the next task created
  in that project gets `index = 1` -- reusing an index previously held
  by a completely different task.
- `TAL-1` today and `TAL-1` tomorrow can refer to entirely different
  tasks if the project was emptied and repopulated in between.

This was confirmed by live observation: moving "test task" out of TAL
emptied the project; the next task created ("test2") received `index 1`,
becoming `TAL-1` -- the same identifier previously held by "test task".

A `GET /tasks/by-ref/TAL-1` endpoint has been proposed in
go-vikunja/vikunja#2694. Without a solution to index reuse (e.g.
an ever-increasing monotonic counter rather than MAX + 1), that endpoint
would be unsafe for use as a durable reference. Until then, always use
the global `id`.

## Mapping principles

1. **Default conservatively.** Unspecified fields stay null. Priority,
   due date, reminders - if the user didn't mention it, don't guess.
2. **Preserve provenance.** Every task captured from Claude Code gets a
   `src:claude-code` label so it's searchable and distinguishable from
   tasks captured through the UI or Linear.
3. **Use native fields for anything Vikunja treats as first-class.**
   Done status, priority, and due dates stay on the task object. Don't
   shadow them with labels (e.g. no `status:done` label).
4. **Use labels for axes Vikunja doesn't model natively.** Customer,
   context, and custom workflow states get labels.
5. **Bulk capture is dry-run by default.** The skill paraphrases what it
   will create before calling `PUT`. Confirmation is required for bulk
   mutation, asked once for the full batch.

## Working-directory to project mapping

The `cwd -> project` binding is recorded **inside the Vikunja project
itself**, in a delimited `tal-meta` block in the project's
`description` field. There is no per-repo state - user repos stay
tal-unaware, no `.task-a-llama/` directory, no pointer file.

### Why server-side

Each slug has its own isolated Vikunja database, so numeric IDs from one
slug cannot be carried to another. Storing the binding inside the Vikunja
project entity makes it naturally environment-scoped (each slug has its
own copy of the binding) and removes the duplicate-state problem that a
local pointer file would introduce. It also keeps the framework aligned
with the API-only access rule (see CLAUDE.md): no host-disk dependencies,
portable to managed/remote Vikunja in the future.

### The tal-meta block

Auto-create writes a description like this:

```
<pre># --- tal-meta (task-a-llama internal - do not edit) ---
path: /Users/brettrandall/src/some-repo
created-by: claude-sonnet-4-6
captured-at: 2026-04-26
# --- end tal-meta ---</pre>
```

The block sits inside `<pre>` so it survives Vikunja's TipTap editor
round-trip (HTML comments may be stripped; plain text inside `<pre>`
is durable). The block header provides the namespace, so keys
(`path:`, `created-by:`, `captured-at:`) are plain. Only `path:` is
consulted by resolution; other fields are informational.

If the user adds prose to the description in the Vikunja UI, the
block stays intact - the skill grep-finds it by its delimiters.

### Resolution algorithm

First match wins:

1. **Overlay alias** (`~/.config/task-a-llama/overlay.yml` under
   `projects.aliases."<basename(PWD)>"`). Titles only.
2. **Description scan**: `GET /api/v1/projects` and find the project
   whose `tal-meta` block has `path: $PWD`.
3. **Title fallback / repair**: search by `basename "$PWD"`; if a
   same-named project exists without the binding, offer to add a
   `tal-meta` block to it (one-prompt repair).
4. **Auto-create**: confirm with the user, then `PUT /projects` with
   a fresh `tal-meta` block in the description.

Damage to the block is recoverable via the title fallback - removal
of the binding doesn't lose the project, just causes the next
resolution to re-bind via prompt.

### Multi-repo to single-project mappings

Use the overlay's `projects.aliases` to point several directory
basenames at the same project title (e.g. several scratch
directories all mapped to `Personal`). The `tal-meta` block holds at
most one `path:`; one binding per project entity.

## Labels: three axes

Labels are the most expressive low-friction dimension Vikunja gives us.
Use three semantic axes, prefix-namespaced:

### `context:*` - who / what domain

One label per customer, team, or broad area:

- `context:moneylion`
- `context:rakuten`
- `context:personal`
- `context:ops`

Labels without the `context:` prefix are allowed (Vikunja doesn't
enforce a scheme) but the skill emits the prefix by default so they
group nicely in the UI.

### `src:*` - where the task came from

- `src:claude-code` (captured from a Claude Code session)
- `src:linear` (pulled in by the Linear sync skill - `references/sync-linear.md`)
- `src:web` (created in the Vikunja UI)
- `src:caldav` (synced from a CalDAV client)

Provenance is useful for reporting ("what did I capture via Claude
Code this week?") and for re-sync logic (e.g. don't overwrite
`src:linear` tasks with local edits).

### `state:*` - lifecycle flags Vikunja doesn't model natively

- `state:waiting` (blocked on someone else)
- `state:next` (queued to start)
- `state:parked` (intentionally dormant)

`done` and priority stay as native fields. Only use `state:*` for flags
Vikunja has no native slot for.

### What NOT to do

- Don't use labels for priority (`priority:high`). Use the native
  `priority` field.
- Don't use labels for completion (`status:done`). Use the native
  `done` flag.
- Don't use labels for due dates (`due:today`). Use `due_date`.

### Open question

The public skills repo (Phase 2) will ship a default label set. Should
the skill auto-create missing labels on first use, or refuse to apply a
label that doesn't exist? Recommendation: **auto-create** for `src:*`
and `state:*` (convention-based, safe); **refuse and warn** for
`context:*` labels not seen before, to avoid typo proliferation
(`context:moneyliion`).

## Priority

Vikunja stores priority as `int64` with no fixed enum but a conventional
0-5 range.

| Value | Meaning |
| --- | --- |
| 0 / null | Unset |
| 1 | Low |
| 2 | Medium-low |
| 3 | Medium |
| 4 | High |
| 5 | Urgent |

The Vikunja UI maps 1-5 to its own priority picker; numeric values above
5 are accepted but not renderable.

**Default when capturing from Claude Code: null (unset).** Raise via
explicit user direction ("make these high priority").

## Due dates

**Default: null.** Only set a `due_date` when the capture request
specifies one ("follow up by Friday", "before the 15th").

When parsing date phrases:

- Relative dates resolve against the user's system timezone (`date +%Z`).
- Ambiguous dates ("Friday") prefer the next future occurrence.
- If parsing fails, ask rather than guess.

## Out of scope for v1 skill

These parts of Vikunja's model are real but off the v1 capture path:

- **Subtasks / dependencies** (`/api/v1/tasks/{id}/relations`) - handled
  in the web UI; the skill stays flat. Users can wire up subtask
  relationships after capture if they want the tree view.
- **Reminders** - single-user on localhost, Vikunja's own reminder
  delivery isn't integrated with anything useful yet. Defer to Phase 3+.
- **Assignees** - single-user, so always the current user.
- **Attachments** - rare for TODO-style workflows. Users who need
  attachments use the web UI.
- **Recurrence** (`repeat_after`) - deferred; set via web UI when
  needed.
- **Kanban bucket positioning** - per-view, out of scope for skill
  capture.

## Resolved policy (Phase 2)

The four design questions originally flagged here (binding storage,
label auto-create, project auto-create UX, batch cap) were resolved
during Phase 2 implementation. Decisions:

1. **Binding storage**: server-side, in a `tal-meta` block embedded
   in the Vikunja project's description. No per-repo files; user
   repos remain tal-unaware. Naturally environment-scoped (each
   stack has its own database) and aligned with the API-only access
   rule. Earlier proposal of a local `.task-a-llama/project` pointer
   file was discarded because numeric IDs leak across the
   production / test stack split.
2. **Label auto-create**: yes for `src:*` and `state:*` (small known
   vocabularies); refuse for `context:*` (typo guard - customer
   labels are pre-seeded via the overlay's `customers:` list).
3. **Project auto-create**: paraphrase + confirm on the first
   capture in a directory; silently resolve on subsequent captures
   via the description scan.
4. **Batch cap**: warn at > 20 tasks per batch; refuse at > 50
   unless the user explicitly types `force`.

The authoritative source is the skill itself:
[`task-a-llama-skills`](https://github.com/javabrett/task-a-llama-skills),
specifically `adapters/claude-code/.claude/skills/tal/SKILL.md`
(safety contract) and `references/capture.md` (project resolution and
label policy algorithms).
