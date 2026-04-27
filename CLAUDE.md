# CLAUDE.md — task-a-llama framework repo

This is the `task-a-llama` framework repository: the infrastructure-as-code for running
a self-hosted Vikunja instance with Claude Code integration.

Read `README.md` first for project overview, structure, and design decisions.

## What this repo is

- Infrastructure layer only: Docker Compose, bootstrap scripts, backup scripts, config schema
- AI-agnostic — knows nothing about Claude Code or MCP directly
- One of four related repos (framework, skills, overlay, data); this is the framework

## What this repo is not

- Not the place for AI skills or prompts — those live in `task-a-llama-skills` (public)
  or `task-a-llama-overlay` (private, inside user dotfiles)
- Not the place for task data — that lives in `task-a-llama-pasture` (private data repo)
- Not a multi-user or team tool — single user, localhost deployment

## Conventions

- Docker images pinned to minor version (e.g. `2.3`), not `latest`; Vikunja tags have no `v` prefix
- Bind mounts, not named volumes, for all persistent data
- Secrets in `.env` (gitignored); shape documented in `.env.example` (committed)
- Cross-repo paths configured in `config.yml` (gitignored); shape in `config.example.yml`
- Scripts live in `bin/`, docs in `docs/`, both under source control
- Follow existing shell style in `bin/` when adding new scripts (bash, `set -euo pipefail`)

## When making changes

- Update `README.md` if design decisions change
- Update `.env.example` and `config.example.yml` when adding new config knobs
- Keep scripts idempotent — they should be safe to re-run
- Preserve the four-repo separation — don't pull skills or data concerns into this repo

## Useful files to read for context

- `README.md` — project overview and design decisions
- `docs/design-decisions.md` — deeper rationale for non-obvious choices
- `docker-compose.yml` — the runtime stack definition
- `config.example.yml` — orchestration config schema

## Vikunja REST conventions

When making Vikunja API calls (via curl or skill operations), always return
a direct URL to the affected resource after any successful mutation:

- Project: `<WEB_BASE>/projects/{id}`
- Task: `<WEB_BASE>/tasks/{id}`
- Comment: `<WEB_BASE>/tasks/{task_id}#comment-{comment_id}`

`WEB_BASE` is `http://localhost:3456` in production and `http://localhost:4567`
in test mode (see `docs/test-stack.md`). The `/tal` skill resolves it from
the active mode's `.env` file.

This applies whether the call is a one-off debug curl or part of a skill
operation. Don't make the user hunt in the UI.

## Production / test stack split

Two isolated Vikunja stacks can run side-by-side:

- Production: `~/vikunja/` (port 3456, container `vikunja`) - the gold copy
- Test: `~/vikunja-test/` (port 4567, container `vikunja-test`) - disposable

All lifecycle scripts (`bin/up.sh`, `down.sh`, `nuke.sh`, `backup.sh`,
`first-run.sh`, `bootstrap.sh`) accept an `[production|test]` argument,
defaulting to `production`. The `/tal` skill switches between them via
`~/.config/task-a-llama/active-mode` (file-based mode signal). See
`docs/test-stack.md` for setup and usage.

## Task ID system

Vikunja has two distinct task identifiers:

- **Global ID** (`task.id`) -- the database primary key, used in all API calls and URLs (e.g. `/tasks/17`). This is the only identifier the skill uses, and the only one that is stable.
- **Project index** (`task.index`) -- a per-project counter shown in the UI as `#10`, or `TAL-10` if the project has an identifier prefix set. Display-only; cannot be used in API calls in released Vikunja versions.

In practice: when referring to a task in a `/tal` prompt, use the global ID from the browser URL bar. The skill will always echo back global IDs and full URLs. The project-scoped `#N` shown in the task heading can be ignored.

**Project index is NOT a stable reference.** The index is assigned as
`MAX(current task indices in project) + 1` (source:
`calculateNextTaskIndex` in `repos/vikunja/pkg/models/tasks.go:860`).
Consequences:

- When a task moves to a new project it gets `MAX + 1` in the
  destination — it does NOT carry its old index.
- When all tasks leave a project, the next task added gets index `1`,
  reusing previously-used indices.
- `TAL-1` today and `TAL-1` tomorrow can refer to entirely different
  tasks if the project was emptied and repopulated in between.

This makes the proposed `GET /tasks/by-ref/TAL-1` endpoint
(go-vikunja/vikunja#2694) potentially dangerous without additional
safeguards -- a caller could silently receive the wrong task. Until
that proposal ships with a solution to this problem, always use the
global `id`.

See also: `docs/vikunja-ui-tweaks.md` for a CSS rule to hide the
confusing project index from the task heading.

## API-only access to Vikunja

The framework and the `/tal` skill access Vikunja exclusively via its
REST API. Do **not** introduce dependencies on:

- Direct reads of `vikunja.db` (the sqlite file under the bind-mounted
  data dir)
- Host filesystem access into the container's data, config, or files dir
- `docker exec` calls that fetch or mutate Vikunja state
- Any other backdoor that bypasses the API

This rule preserves the option of running task-a-llama against a
managed or remote Vikunja instance later, where shell or filesystem
access to the host is unavailable. A `bin/` script that reads
`vikunja.db` directly, or a skill operation that shells into the
container to grep something out, is a violation - flag it before
proceeding.

Where state belongs:

- **Server-side state** (task data, project bindings, label
  vocabularies) lives in Vikunja entities accessed via the API:
  `Project.description` for the `cwd -> project_id` binding (see the
  `tal-meta` block convention in the skill), labels for
  cross-cutting tags, etc.
- **Client-side state** (the active mode, any future caches) lives
  under `~/.config/task-a-llama/`.

`docker compose` lifecycle commands (`up`, `down`, `logs`, `exec sh`
for human debugging) are fine - they manage the runtime, they don't
poke Vikunja's data behind its back.

## Environment-bound state convention

Two Vikunja stacks run side-by-side (production and test) with
independent databases. Any client-side file that holds stack-specific
values (numeric IDs, tokens, base URLs) must be either:

1. **Inside a mode-scoped directory** - e.g. `~/vikunja/.env` and
   `~/vikunja-test/.env` are partitioned by stack root.
2. **Namespaced by mode in its filename** - e.g. a hypothetical
   future cache at `~/.config/task-a-llama/foo.json` for production
   would have a sibling `~/.config/task-a-llama/foo.test.json` for
   test. The skill picks the file by reading `active-mode`.

`active-mode` itself is the global selector and is correctly the only
unscoped file under `~/.config/task-a-llama/`.

User repos must remain tal-unaware: do not introduce per-repo
`.task-a-llama/` directories or pointer files. Project bindings live
in Vikunja project descriptions (see the skill's `tal-meta` block
convention), which are environment-scoped by construction.

## Related repos and how to locate them

There are four task-a-llama repos (framework, skills, overlay, data).
Their local paths are **user-configured** and must not be assumed.

### Canonical source: config.yml

`config.yml` (gitignored; schema in `config.example.yml`) is the
authoritative map of all repo paths. Read it first:

```bash
cat ~/src/task-a-llama/config.yml
```

The `sources:` block lists `local:` paths for `public_skills`,
`private_skills`, and `data`. Use these paths when you need to read
or modify source files in a sibling repo.

### Fast lookup: follow the stow symlinks

Skills are stowed into `~/.claude/skills/`. Each entry is a symlink
pointing directly at its source repo:

```bash
ls -la ~/.claude/skills/
```

For example: `~/.claude/skills/tal -> <skills-repo>/adapters/claude-code/.claude/skills/tal`

Following any symlink gives the source repo root without reading
`config.yml`.

### What to read for skill behaviour

After a `/clear` or in a fresh session, the stowed files at
`~/.claude/skills/tal/` are always reachable and always current
(they are the source, via symlink). Read:

- `~/.claude/skills/tal/SKILL.md` -- entry point and operation index
- `~/.claude/skills/tal/references/*.md` -- detailed operation specs

The overlay config (user-specific label vocabulary, project aliases,
conventions) lives at `~/.config/task-a-llama/overlay.yml`.

## Source references

Vikunja's own source code is checked out at `repos/vikunja/` (gitignored).
Consult it directly when you need authoritative answers about Vikunja's API,
schema, or internal behaviour — rather than guessing or searching the web.
This is a standing convention for this repo.
