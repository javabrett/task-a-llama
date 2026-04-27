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

Proposal: **auto-create with manual override via a pointer file**.

### Default: auto-create

When the skill needs a project and no pointer file exists, it:

1. Takes `basename "$PWD"` as the project title candidate.
2. Searches existing Vikunja projects by exact title match
   (`GET /api/v1/projects?s=<title>`).
3. If a match exists, uses it. If not, creates a new project with that
   title (`PUT /api/v1/projects`).
4. On first-use for a directory, writes a pointer file so subsequent
   captures skip the lookup.

Why this default: zero friction for one-off repos, deterministic per-
directory.

### Override: pointer file

Users can override by creating `.task-a-llama/project` in the repo root:

```
# Either a numeric id:
42

# or an exact project title:
MoneyLion - Ingestion
```

The skill reads the first non-comment line. Pointer files can be
committed to the repo (public intent) or gitignored (private intent) -
the skill doesn't care.

The pointer file is how you:

- Point multiple repos at a single Vikunja project (e.g. one "Personal"
  project used across several scratch repos)
- Use a project with a title that doesn't match `basename "$PWD"`
- Guard against accidental project creation in throwaway directories

### Open question

Should `.task-a-llama/` be a committed convention (documented in
project CLAUDE.md files) or a gitignored personal thing (added to
`~/.gitignore_global`)? The former makes the mapping shareable across
a team; the latter keeps Vikunja metadata out of the repo entirely.
Recommendation: **gitignored by default**, since `task-a-llama` is
single-user. Users who want team-shared mappings opt in.

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
- `src:linear` (pulled in by the Linear sync skill - Phase 3)
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

- Relative dates resolve against the user's `TZ` from `.env`.
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

## Open questions (summary)

Explicit decisions wanted before Phase 2 skill implementation:

1. `.task-a-llama/project` pointer file: committed convention or
   gitignored personal convention? (Recommendation: gitignored.)
2. Auto-create labels on first use: yes for `src:*` and `state:*`,
   refuse for `context:*`? Or uniformly one policy?
3. Project auto-create: prompt on first use, or silently create?
   (Recommendation: show-and-confirm on the first batch, silently
   create on subsequent batches in the same directory once a pointer
   file exists.)
4. Should the skill cap bulk-capture batch size (e.g. warn on > 20
   at once) to catch prompt-injection-style attempts?

Answers to these will land in the Phase 2 skill itself as comments in
`SKILL.md` or as config knobs in a skill-side YAML - not in this
framework repo.
